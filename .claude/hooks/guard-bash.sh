#!/usr/bin/env bash
# PreToolUse (Bash): applies the write policy to shell writes, blocks shell reads of secrets, and
# catches denied git forms that prefix rules miss. Exit 2 blocks and shows stderr to Claude.
#
# Best effort by design. It lexes the command into simple commands and looks only at the argv of
# commands it knows, never at the raw string. Interpreter one-liners and targets holding a variable
# or a glob can't be resolved: they pass and are logged, and so does a command it can't lex.
#
# A PreToolUse timeout doesn't block: a command that outlasts the hook runs unchecked and unlogged.
# So no forks in the lexer, and hard limits below. Past a limit the command counts as unlexable.
# No -u: bash 3.2 calls an empty array unset, and a crash here would let the command through.
set -o pipefail
HOOK_INPUT="$(cat)"
. "$(dirname "$0")/_lib.sh"

LOG="$(dirname "$0")/../../.agent/state/guard-bash.log"
CMD=""        # the whole command, for the log
CWD=""        # where relative targets resolve; moved by cd, scoped with `local` in subshells
CWD_OK=1      # 0 after `cd $X`: relative targets can't be resolved until an absolute cd
NEST=0        # sh -c / eval depth
LEX_BAD=0     # set by the lexer on an unterminated quote or paren
LONG_VALS=""  # long flags that take the next word as a value, for scan_opts
POS=(); OPTS=(); SKIP=0; REPLY=""

# Limits. Every loop in the lexer spends STEPS, so it ends even if it stops advancing. One step can
# touch the whole string (bash 3.2 has no cheap substring), so the budget shrinks as the command
# grows: LEX_WORK / length. A single ${x%%pattern} can't be stopped and is quadratic, so searches
# only ever run on a WINDOW of the string. A checked target costs forks, not steps, so it has its
# own count and a clock, well inside the 30 seconds in settings.json.
LEX_WORK=4000000000
STEPS=0
CHECKS=200
DEADLINE=15
NOTES=50      # a log line costs a fork too
MAX_DEPTH=64  # nested parens: a function call each
WINDOW=8192
MAX_WORD=16384
MAX_PATH=4096
OVER=0

block() { echo "BLOCKED: $1" >&2; exit 2; }

# note <reason> : a pass we couldn't check. Logging must never get in the way of the command.
note() {
  (( NOTES-- > 0 )) || return 0
  # Cut first: ${x//} is quadratic on 3.2, and on a whole command it would outlast the hook.
  local line="${CMD:0:200}"
  line="${line//$'\n'/ }"
  { printf '%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$1" "$line" >> "$LOG"; } 2>/dev/null
}

# over_budget : give up on this command. Ends every lexer loop, here and in the callers.
over_budget() {
  OVER=1; STEPS=0; CHECKS=0; LEX_BAD=1; I=$N
}

# spend_check : false once there's no budget left for another target.
spend_check() {
  if (( CHECKS-- > 0 && SECONDS < DEADLINE )); then return 0; fi
  over_budget
  return 1
}

# ---------------- targets ----------------

# resolve_word <word> : sets REPLY to a path for the policy. Returns non-zero when there is nothing
# to check: a device that is always fine, or a word only the shell can expand.
resolve_word() {
  local w="$1"
  if [ ${#w} -gt "$MAX_PATH" ]; then note "target too long"; return 1; fi
  case "$w" in
    ''|-|/dev/null|/dev/stdout|/dev/stderr|/dev/fd/*) return 1 ;;
    *'$'*|*'`'*|*'*'*|*'?'*|*'['*|*'{'*,*'}'*) note "unresolved target: $w"; return 1 ;;
    '~'|'~/'*) w="${HOME:-}${w#'~'}" ;;
    '~'*) note "unresolved target: $w"; return 1 ;;
  esac
  case "$w" in
    /*) ;;
    *) if [ "$CWD_OK" != 1 ]; then note "unknown cwd for target: $w"; return 1; fi ;;
  esac
  REPLY="$w"
}

# abs_word <word> : like resolve_word, with REPLY absolute.
abs_word() {
  resolve_word "$1" || return 1
  case "$REPLY" in /*) ;; *) REPLY="$CWD/$REPLY" ;; esac
}

write_check() {
  resolve_word "$1" || return 0
  spend_check || return 0
  path_policy "$REPLY" "$CWD" || exit 2
}

# read_check <word> : narrower than the write policy. Only the secrets list applies, the committed
# templates are fine, and it holds outside a repo too: a key is a key wherever it lies.
read_check() {
  local p dir root rel
  abs_word "$1" || return 0
  spend_check || return 0
  p="$(canon_path "$REPLY")"
  case "${p##*/}" in .env.example|.env.sample|.env.template) return 0 ;; esac
  dir="$(dirname "$p")"; while [ ! -d "$dir" ]; do dir="$(dirname "$dir")"; done
  root="$(repo_root "$dir")"
  rel="$p"
  [ -n "$root" ] && rel="${p#"$root"/}"
  [ -d "$p" ] && rel="$rel/_"                   # `cp -r secrets x` copies what's under it
  if is_secret "$rel"; then
    block "'$rel' is a protected path (secrets). Don't read it from the shell."
  fi
}

# set_cwd <word> : what `cd <word>` does to where relative targets resolve.
set_cwd() {
  case "$1" in
    -|*'$'*|*'`'*|*'*'*|*'?'*|*'['*) CWD_OK=0 ;;
    '~'|'~/'*) CWD="${HOME:-}${1#'~'}"; CWD_OK=1 ;;
    /*) CWD="$1"; CWD_OK=1 ;;
    *) CWD="$CWD/$1" ;;
  esac
}

# ---------------- argv helpers ----------------

# scan_opts <value letters> <args...> : splits args into POS (operands) and OPTS. A short flag in
# <value letters> takes the rest of its cluster or the next word, and lands in OPTS as -x<value>.
# A long flag named in LONG_VALS takes the next word, and lands as --name=<value>.
scan_opts() {
  local vals="$1" a rest l; shift
  POS=(); OPTS=()
  while [ $# -gt 0 ]; do
    a="$1"; shift
    case "$a" in
      --) POS+=("$@"); return ;;
      --*) case " $LONG_VALS " in
             *" $a "*) OPTS+=("$a=$1"); [ $# -gt 0 ] && shift ;;
             *) OPTS+=("$a") ;;
           esac ;;
      -?*) rest="${a#-}"
           while [ -n "$rest" ]; do
             l="${rest:0:1}"; rest="${rest:1}"
             case "$vals" in
               *"$l"*) if [ -z "$rest" ] && [ $# -gt 0 ]; then rest="$1"; shift; fi
                       OPTS+=("-$l$rest"); rest="" ;;
               *) OPTS+=("-$l") ;;
             esac
           done ;;
      *) POS+=("$a") ;;
    esac
  done
}

# opts_end <value letters> <args...> : sets SKIP to how many leading args are the wrapper's options.
opts_end() {
  local vals="$1" a rest l; shift
  SKIP=0
  while [ $# -gt 0 ]; do
    a="$1"
    case "$a" in
      --) SKIP=$((SKIP + 1)); return ;;
      --*) ;;
      -?*) rest="${a#-}"
           while [ -n "$rest" ]; do
             l="${rest:0:1}"; rest="${rest:1}"
             case "$vals" in
               *"$l"*) if [ -z "$rest" ] && [ $# -gt 1 ]; then shift; SKIP=$((SKIP + 1)); fi
                       rest="" ;;
             esac
           done ;;
      *) return ;;
    esac
    shift; SKIP=$((SKIP + 1))
  done
}

is_assignment() {
  case "$1" in [A-Za-z_]*=*) ;; *) return 1 ;; esac
  case "${1%%=*}" in *[!A-Za-z0-9_+]*) return 1 ;; esac
}

# ---------------- known commands ----------------

cmd_cd() {
  shift
  scan_opts "" "$@"
  if [ ${#POS[@]} -gt 0 ]; then set_cwd "${POS[0]}"; else set_cwd "${HOME:-/}"; fi
}

# cmd_writer <value letters> <args...> : every operand is a write target.
cmd_writer() {
  local vals="$1" a; shift
  scan_opts "$vals" "$@"
  for a in "${POS[@]}"; do write_check "$a"; done
}

# cmd_reader <args...> : every operand may be read. Flag values among them do no harm.
cmd_reader() {
  local a
  scan_opts "" "$@"
  for a in "${POS[@]}"; do read_check "$a"; done
}

# cmd_pattern <value letters> <args...> : grep and friends. The first operand is the pattern,
# unless a flag named it.
cmd_pattern() {
  local vals="$1" a pattern_given=0; shift
  LONG_VALS="--regexp --file --include --exclude --exclude-dir --glob --type --max-count --context"
  scan_opts "$vals" "$@"
  LONG_VALS=""
  for a in "${OPTS[@]}"; do
    case "$a" in
      -e*|--regexp=*) pattern_given=1 ;;
      -f*) pattern_given=1; read_check "${a#-f}" ;;
      --file=*) pattern_given=1; read_check "${a#--file=}" ;;
    esac
  done
  [ "$pattern_given" = 1 ] || POS=("${POS[@]:1}")
  for a in "${POS[@]}"; do read_check "$a"; done
}

cmd_awk() {
  local a program_given=0
  scan_opts "fvF" "$@"
  for a in "${OPTS[@]}"; do case "$a" in -f*) program_given=1 ;; esac; done
  [ "$program_given" = 1 ] || POS=("${POS[@]:1}")
  for a in "${POS[@]}"; do read_check "$a"; done
}

# cmd_copy <argv...> : cp, mv, ln and install. Sources may be secrets, the destination is a write,
# and mv's source is a write too: it disappears from where it was.
cmd_copy() {
  local tool="${1##*/}" vals="tS" dest="" into=0 notdir=0 n s o
  local -a srcs=()
  shift
  [ "$tool" = install ] && vals="tSmogfB"
  scan_opts "$vals" "$@"
  for o in "${OPTS[@]}"; do
    case "$o" in
      -t*) dest="${o#-t}"; into=1 ;;
      --target-directory=*) dest="${o#*=}"; into=1 ;;
      -T|--no-target-directory) notdir=1 ;;
      -d|--directory) [ "$tool" = install ] && { for s in "${POS[@]}"; do write_check "$s"; done; return; } ;;
    esac
  done
  n=${#POS[@]}
  [ "$n" -gt 0 ] || return 0
  if [ -n "$dest" ]; then srcs=("${POS[@]}")
  elif [ "$n" -gt 1 ]; then dest="${POS[n-1]}"; srcs=("${POS[@]:0:n-1}")
  elif [ "$tool" = ln ]; then dest="."; into=1; srcs=("${POS[@]}")
  else read_check "${POS[0]}"; return
  fi
  case "$dest" in */) into=1 ;; esac
  if [ "$notdir" = 0 ] && abs_word "$dest" && [ -d "$REPLY" ]; then into=1; fi

  for s in "${srcs[@]}"; do
    read_check "$s"
    if [ "$tool" = mv ]; then
      write_check "$s"
      # A directory's own path isn't on any list, what's under it is: `mv .claude/hooks x`.
      if abs_word "$s" && [ -d "$REPLY" ]; then write_check "$s/_"; fi
    fi
    s="${s%/}"
    if [ "$into" = 1 ]; then write_check "${dest%/}/${s##*/}"; else write_check "$dest"; fi
  done
}

cmd_dd() {
  local a; shift
  for a in "$@"; do
    case "$a" in
      of=*) write_check "${a#of=}" ;;
      if=*) read_check "${a#if=}" ;;
    esac
  done
}

# sed: reads its files, and writes them with -i. Parsed by hand because BSD's -i takes a separate
# suffix word (`sed -i '' ...`) and GNU's doesn't.
cmd_sed() {
  local a rest l script_given=0 inplace=0
  local -a files=()
  shift
  while [ $# -gt 0 ]; do
    a="$1"; shift
    case "$a" in
      --) files+=("$@"); break ;;
      --in-place|--in-place=*) inplace=1 ;;
      --expression=*) script_given=1 ;;
      --file=*) script_given=1; read_check "${a#--file=}" ;;
      --expression|--file) script_given=1; [ $# -gt 0 ] && shift ;;
      --*) ;;
      -?*) rest="${a#-}"
           while [ -n "$rest" ]; do
             l="${rest:0:1}"; rest="${rest:1}"
             case "$l" in
               i) inplace=1
                  # BSD's suffix word: '' always, .bak only where a script must still follow.
                  # Anywhere else a dotted word is the file, as GNU reads it. A dotted word taken
                  # for a suffix is still checked as a read: GNU would edit it.
                  if [ -z "$rest" ] && [ $# -gt 0 ]; then
                    case "$1" in
                      '') shift ;;
                      */*) ;;
                      .*) if [ "$script_given" = 0 ] && [ ${#files[@]} = 0 ] && [ $# -gt 1 ]; then
                            read_check "$1"; shift
                          fi ;;
                    esac
                  fi
                  rest="" ;;
               e|f) script_given=1
                    if [ -z "$rest" ] && [ $# -gt 0 ]; then rest="$1"; shift; fi
                    [ "$l" = f ] && read_check "$rest"
                    rest="" ;;
               l) [ -z "$rest" ] && [ $# -gt 0 ] && shift; rest="" ;;
             esac
           done ;;
      *) files+=("$a") ;;
    esac
  done
  [ "$script_given" = 1 ] || files=("${files[@]:1}")
  for a in "${files[@]}"; do
    read_check "$a"
    [ "$inplace" = 1 ] && write_check "$a"
  done
}

# perl: only -i is ours. Reading through an interpreter is out of scope.
cmd_perl() {
  local a rest l script_given=0 inplace=0
  local -a files=()
  shift
  while [ $# -gt 0 ]; do
    a="$1"; shift
    case "$a" in
      --) files+=("$@"); break ;;
      -?*) rest="${a#-}"
           while [ -n "$rest" ]; do
             l="${rest:0:1}"; rest="${rest:1}"
             case "$l" in
               i) inplace=1; rest="" ;;
               e|E) script_given=1; [ -z "$rest" ] && [ $# -gt 0 ] && shift; rest="" ;;
               I|M|m|x|C|d|D|V) rest="" ;;
             esac
           done ;;
      *) files+=("$a") ;;
    esac
  done
  [ "$inplace" = 1 ] || return 0
  [ "$script_given" = 1 ] || files=("${files[@]:1}")
  for a in "${files[@]}"; do write_check "$a"; done
}

# cmd_shell <argv...> : sh -c '<string>', inspected as a command of its own.
cmd_shell() {
  local CWD="$CWD" CWD_OK="$CWD_OK" a run=0
  shift
  while [ $# -gt 0 ]; do
    a="$1"; shift
    case "$a" in
      -o|+o|-O|+O|--rcfile|--init-file) [ $# -gt 0 ] && shift ;;
      --*) ;;
      -*c*) run=1 ;;
      [-+]*) ;;
      *) [ "$run" = 1 ] && inspect_string "$a"
         return ;;
    esac
  done
}

# inspect_string <text> : one level deep. A string inside a string passes and is logged.
inspect_string() {
  if [ "$NEST" -ge 1 ]; then note "shell string nested too deep"; return 0; fi
  local NEST=1
  lex_string "$1"
}

# ---------------- git ----------------

cmd_git() {
  local CWD="$CWD" CWD_OK="$CWD_OK" sub
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      -C) set_cwd "$2"; shift; [ $# -gt 0 ] && shift ;;
      -c|--git-dir|--work-tree|--namespace|--config-env|--super-prefix|--attr-source)
        shift; [ $# -gt 0 ] && shift ;;
      -*) shift ;;
      *) break ;;
    esac
  done
  sub="$1"; [ $# -gt 0 ] && shift
  case "$sub" in
    push|reset)
      block "'git $sub' is denied to the agent, in any form. Give the user the exact command to run with the ! prefix." ;;
    add) git_add "$@" ;;
    apply) git_apply "$@" ;;
    checkout) git_checkout "$@" ;;
    restore) git_restore "$@" ;;
    *'$'*|*'`'*) note "unresolved git subcommand: $sub" ;;
  esac
}

# git takes any unique prefix of a long flag, so --forc is --force.
git_add() {
  local a
  for a in "$@"; do
    case "$a" in
      --) return ;;
      --f|--fo|--for|--forc|--force) ;;
      --*) continue ;;
      -*f*) ;;
      *) continue ;;
    esac
    block "'git add $a' is denied: it stages ignored files, secrets included. If it's needed, give the user the exact command to run with the ! prefix."
  done
}

git_checkout() {
  local a i=0
  local -a pos=()
  while [ $# -gt 0 ]; do
    a="$1"; shift
    case "$a" in
      --) for a in "$@"; do write_check "$a"; done; return ;;
      -b|-B|--orphan|--detach|-d) return ;;
      -*) ;;
      *) pos+=("$a") ;;
    esac
  done
  # No `--`: the first word is a branch or a tree-ish unless it's on disk, the rest are paths.
  for a in "${pos[@]}"; do
    if [ "$i" -gt 0 ]; then write_check "$a"
    elif abs_word "$a" && [ -e "$REPLY" ]; then write_check "$a"
    fi
    i=$((i + 1))
  done
}

git_restore() {
  local a staged=0 worktree=0
  LONG_VALS="--source"
  scan_opts "s" "$@"
  LONG_VALS=""
  for a in "${OPTS[@]}"; do
    case "$a" in
      -S|--staged) staged=1 ;;
      -W|--worktree) worktree=1 ;;
    esac
  done
  [ "$staged" = 1 ] && [ "$worktree" = 0 ] && return 0   # the index only, no file changes
  for a in "${POS[@]}"; do write_check "$a"; done
}

# git_apply: the targets are inside the patch. Paths in a git patch count from the top of the repo.
git_apply() {
  local a strip=1 prefix="" root="" seen="" prev="" line
  scan_opts "pC" "$@"
  for a in "${OPTS[@]}"; do
    case "$a" in
      --check|--stat|--numstat|--summary) return 0 ;;
      -p*) strip="${a#-p}" ;;
      --directory=*) prefix="${a#*=}/" ;;
    esac
  done
  if [ ${#POS[@]} -eq 0 ]; then note "git apply from stdin"; return 0; fi
  spend_check || return 0
  if [ "$CWD_OK" = 1 ]; then root="$(repo_root "$CWD")"; fi
  for a in "${POS[@]}"; do
    abs_word "$a" || continue
    if [ ! -f "$REPLY" ]; then note "git apply: no such patch: $a"; continue; fi
    while IFS= read -r line || [ -n "$line" ]; do
      (( STEPS-- > 0 )) || { over_budget; return 0; }
      [ ${#line} -le "$MAX_PATH" ] || continue
      case "$line" in
        '+++ '*) case "$prev" in
                   '--- '*) patch_target "${prev#--- }"; patch_target "${line#+++ }" ;;
                 esac ;;
        'diff --git '*) patch_target "${line##* }" ;;
        'rename from '*|'rename to '*|'copy to '*) strip=0 patch_target "${line#* * }" ;;
      esac
      prev="$line"
    done < "$REPLY"
  done
}

# patch_target <path as the patch spells it> : uses strip, prefix, root and seen from git_apply.
patch_target() {
  local p="${1%%$'\t'*}" n="$strip"
  p="${p#\"}"; p="${p%\"}"
  [ "$p" = /dev/null ] && return 0
  while [ "$n" -gt 0 ]; do
    case "$p" in */*) p="${p#*/}" ;; *) break ;; esac
    n=$((n - 1))
  done
  p="$prefix$p"
  [ -n "$root" ] && p="$root/$p"
  case "$seen" in *$'\n'"$p"$'\n'*) return 0 ;; esac
  seen="$seen"$'\n'"$p"$'\n'
  write_check "$p"
}

# ---------------- one simple command ----------------

# check_simple <argv...> : every simple command comes through here, with quotes removed. Peels what
# only wraps the real command, so `env X=1 nice git push` is still seen as git, then dispatches on
# the basename of argv[0]. Anything not listed is none of our business.
check_simple() {
  local name vals
  while [ $# -gt 0 ]; do
    case "$1" in
      if|then|elif|else|do|while|until|'!'|'{'|'}'|fi|done|esac) shift; continue ;;
    esac
    if is_assignment "$1"; then shift; continue; fi
    name="${1##*/}"
    case "$name" in
      env) vals="uCS" ;;
      nice) vals="n" ;;
      time) vals="o" ;;
      timeout) vals="sk" ;;
      xargs) vals="IdEJLnPRsS" ;;
      exec) vals="a" ;;
      command|builtin|nohup) vals="" ;;
      *) break ;;
    esac
    shift
    opts_end "$vals" "$@"
    shift "$SKIP"
    if [ "$name" = timeout ] && [ $# -gt 0 ]; then shift; fi   # the duration
  done
  [ $# -gt 0 ] || return 0

  case "$1" in
    *'$'*|*'`'*) note "unresolved command: $1"; return 0 ;;
  esac
  name="${1##*/}"
  case "$name" in
    cd|pushd) cmd_cd "$@" ;;
    popd) CWD_OK=0 ;;
    git) cmd_git "$@" ;;
    sh|bash|zsh|dash|ksh) cmd_shell "$@" ;;
    eval) shift; inspect_string "$*" ;;
    tee) shift; cmd_writer "" "$@" ;;
    touch) shift; cmd_writer "dtrA" "$@" ;;
    truncate) shift; LONG_VALS="--size --reference"; cmd_writer "sr" "$@"; LONG_VALS="" ;;
    cp|mv|ln|install) cmd_copy "$@" ;;
    dd) cmd_dd "$@" ;;
    sed|gsed) cmd_sed "$@" ;;
    perl) cmd_perl "$@" ;;
    grep|egrep|fgrep) shift; cmd_pattern "efmABCdD" "$@" ;;
    rg) shift; cmd_pattern "efgtTmABCjMrE" "$@" ;;
    awk|gawk|mawk|nawk) shift; cmd_awk "$@" ;;
    cat|tac|nl|head|tail|less|more|bat|od|xxd|hexdump|strings|base64|base32|sort|uniq|cut|paste|fold|rev|diff|cmp|comm|source|.)
      shift; cmd_reader "$@" ;;
  esac
}

# check_redirect <op> <target>
check_redirect() {
  case "$1" in
    '<') read_check "$2" ;;
    '<>') read_check "$2"; write_check "$2" ;;
    '<&'|'>&') # &N and &- duplicate a descriptor. `>&file` is a write.
      case "$2" in *[!0-9-]*) [ "$1" = '>&' ] && write_check "$2" ;; esac ;;
    *) write_check "$2" ;;
  esac
}

# ---------------- lexer ----------------
# One pass over the string in S, cursor I, length N. The word in progress (w, has), the simple
# command in progress (A, RO, RT), the redirect waiting for its word (pend) and the heredocs waiting
# for their newline (HD) are locals of lex_list, so a nested $(...) gets its own by dynamic scope.

DQ_STOP='["\\$`]*'    # what ends a run of plain characters inside double quotes
S=""; I=0; N=0; DEPTH=0

# lex_string <text> : lexes and inspects a whole command line.
lex_string() {
  local S="$1" I=0 N=${#1}
  lex_list ""
  if [ "$OVER" = 1 ]; then NOTES=1; note "unlexable: over budget"
  elif [ "$LEX_BAD" = 1 ]; then LEX_BAD=0; note "unlexable"
  fi
}

# lex_list <closer> : walks a list of commands. With closer ")" it stops at the matching paren.
lex_list() {
  local closer="$1" c n w="" has=0 pend=""
  local -a A=() RO=() RT=() HD=()
  while (( I < N )); do
    (( STEPS-- > 0 )) || { over_budget; break; }
    c="${S:I:1}"
    case "$c" in
      ' '|$'\t') end_word; I=$((I + 1)) ;;
      $'\n') end_cmd; I=$((I + 1)); skip_heredocs ;;
      ';') end_cmd; I=$((I + 1)) ;;
      '|') end_cmd
           case "${S:I+1:1}" in '|'|'&') I=$((I + 2)) ;; *) I=$((I + 1)) ;; esac ;;
      '&') case "${S:I+1:1}" in
             '&') end_cmd; I=$((I + 2)) ;;
             '>') end_word
                  if [ "${S:I+2:1}" = '>' ]; then pend='&>>'; I=$((I + 3))
                  else pend='&>'; I=$((I + 2)); fi ;;
             *) end_cmd; I=$((I + 1)) ;;
           esac ;;
      '(') if [ "$has" = 0 ] && [ ${#A[@]} = 0 ] && [ "${S:I+1:1}" = '(' ]; then
             skip_arith                         # (( x > 3 )) has no redirects in it
           else
             end_cmd; I=$((I + 1)); nested
           fi ;;
      ')') end_cmd; I=$((I + 1))
           # Unmatched at the top: a case pattern. The words before it were never a command.
           [ -n "$closer" ] && return 0 ;;
      '<'|'>') start_redirect ;;
      '#') if [ "$has" = 1 ]; then w+="$c"; I=$((I + 1)); else skip_comment; fi ;;
      '\') n="${S:I+1:1}"
           if [ "$n" != $'\n' ]; then w+="$n"; has=1; fi
           I=$((I + 2)) ;;
      "'") read_squote ;;
      '"') read_dquote ;;
      '$') read_dollar "" ;;
      '`') read_backtick ;;
      *) w+="$c"; has=1; I=$((I + 1)) ;;
    esac
  done
  if [ -n "$closer" ]; then LEX_BAD=1; fi
  [ "$LEX_BAD" = 1 ] || end_cmd
}

# nested : a (...) or $(...) body. A cd in there doesn't reach the commands after it.
nested() {
  if [ "$DEPTH" -ge "$MAX_DEPTH" ]; then over_budget; return 0; fi
  local CWD="$CWD" CWD_OK="$CWD_OK" DEPTH=$((DEPTH + 1))
  lex_list ')'
}

end_word() {
  [ "$has" = 1 ] || return 0
  # Past this size pattern work on a word gets slow, and no path or flag is that long. The $ makes
  # it unresolved, same as a variable.
  if [ ${#w} -gt "$MAX_WORD" ]; then note "word too long"; w='$'; fi
  case "$pend" in
    '') A+=("$w") ;;
    '<<'|'<<-') HD+=("$pend:$w") ;;
    '<<<') ;;
    *) RO+=("$pend"); RT+=("$w") ;;
  esac
  pend=""; w=""; has=0
}

end_cmd() {
  local i=0
  end_word
  pend=""
  # Inside [[ ]], < and > compare strings.
  if [ ${#A[@]} = 0 ] || [ "${A[0]}" != '[[' ]; then
    while [ "$i" -lt ${#RO[@]} ]; do
      check_redirect "${RO[i]}" "${RT[i]}"
      i=$((i + 1))
    done
  fi
  [ ${#A[@]} = 0 ] || check_simple "${A[@]}"
  A=(); RO=(); RT=()
}

start_redirect() {
  # 2>file: the digits are the descriptor, not a word.
  if [ "$has" = 1 ]; then
    case "$w" in
      *[!0-9]*) end_word ;;
      *) w=""; has=0 ;;
    esac
  fi
  case "${S:I:3}" in
    '<<<'|'<<-') pend="${S:I:3}"; I=$((I + 3)); return ;;
  esac
  case "${S:I:2}" in
    '<('|'>(') I=$((I + 2)); nested; w+='$'; has=1 ;;   # process substitution
    '<<'|'<&'|'<>'|'>>'|'>&'|'>|') pend="${S:I:2}"; I=$((I + 2)) ;;
    *) pend="${S:I:1}"; I=$((I + 1)) ;;
  esac
}

# skip_comment : the cursor is on the #. Stops at the newline, which ends the command as usual.
skip_comment() {
  local rest line
  while (( I < N )); do
    (( STEPS-- > 0 )) || { over_budget; return 0; }
    rest="${S:I:WINDOW}"; line="${rest%%$'\n'*}"; I=$((I + ${#line}))
    [ ${#line} = ${#rest} ] || return 0
  done
}

# skip_heredocs : the cursor is just past a newline. Bodies are text, never commands.
skip_heredocs() {
  local h line rest
  [ ${#HD[@]} -gt 0 ] || return 0
  for h in "${HD[@]}"; do
    case "$h" in
      '<<-:'*)                                  # tabs before the closing line: a line at a time
        while (( I < N )); do
          (( STEPS-- > 0 )) || { over_budget; return 0; }
          rest="${S:I:WINDOW}"; line="${rest%%$'\n'*}"; I=$((I + ${#line} + 1))
          line="${line#"${line%%[!$'\t']*}"}"
          [ "$line" = "${h#*:}" ] && break
        done ;;
      *) skip_body "${h#*:}" ;;
    esac
  done
  HD=()
}

# skip_body <delimiter> : bodies are the bulk of a big command, so this searches for the closing
# line a window at a time, not line by line. Windows overlap by one closing line, so one that
# falls across two windows is still seen. No closing line: the body runs to the end of input.
skip_body() {
  local delim="$1" nl=$'\n' lead=$'\n' tail win found keep=$((${#1} + 2))
  if [ "$keep" -gt $((WINDOW / 2)) ]; then over_budget; return 0; fi
  while (( I < N )); do
    (( STEPS-- > 0 )) || { over_budget; return 0; }
    win="${S:I:WINDOW}"
    tail=""; if (( I + ${#win} >= N )); then tail="$nl"; fi
    win="$lead$win$tail"
    found="${win%%"$nl$delim$nl"*}"
    if [ ${#found} != ${#win} ]; then
      I=$((I + ${#found} - ${#lead} + ${#delim} + 2)); return 0
    fi
    if [ -n "$tail" ]; then I=$N; return 0; fi
    I=$((I + WINDOW - keep)); lead=""
  done
}

# skip_arith : the cursor is on the first paren of (( or $((.
skip_arith() {
  local depth=0
  while (( I < N )); do
    (( STEPS-- > 0 )) || { over_budget; return 0; }
    case "${S:I:1}" in
      '(') depth=$((depth + 1)) ;;
      ')') depth=$((depth - 1))
           if [ "$depth" = 0 ]; then I=$((I + 1)); return 0; fi ;;
    esac
    I=$((I + 1))
  done
  LEX_BAD=1
}

read_squote() {
  local rest seg
  has=1; I=$((I + 1))
  while :; do
    (( STEPS-- > 0 )) || { over_budget; return 0; }
    rest="${S:I:WINDOW}"
    seg="${rest%%\'*}"
    w+="$seg"; I=$((I + ${#seg}))
    if (( I >= N )); then LEX_BAD=1; return 0; fi
    if [ "${S:I:1}" = "'" ]; then I=$((I + 1)); return 0; fi
  done
}

read_dquote() {
  local rest seg n
  has=1; I=$((I + 1))
  while :; do
    (( (STEPS -= 3) > 0 )) || { over_budget; return 0; }   # reads S three times round this loop
    rest="${S:I:WINDOW}"
    # shellcheck disable=SC2295
    seg="${rest%%$DQ_STOP}"
    w+="$seg"; I=$((I + ${#seg}))
    if (( I >= N )); then LEX_BAD=1; return 0; fi
    case "${S:I:1}" in
      '"') I=$((I + 1)); return 0 ;;
      '\') n="${S:I+1:1}"
           case "$n" in
             '"'|'\'|'$'|'`') w+="$n" ;;
             $'\n') ;;
             *) w+="\\$n" ;;
           esac
           I=$((I + 2)) ;;
      '$') read_dollar dq ;;
      '`') read_backtick ;;
    esac
  done
}

# read_dollar <"dq" inside double quotes> : every form leaves a $ in the word, so a target built
# from one counts as unresolved. A command substitution is walked on the way past.
read_dollar() {
  local rest seg
  has=1
  case "${S:I+1:1}" in
    '(') if [ "${S:I+2:1}" = '(' ]; then I=$((I + 1)); skip_arith
         else I=$((I + 2)); nested; fi
         w+='$' ;;
    '{') rest="${S:I:WINDOW}"
         case "$rest" in *'}'*) ;; *) LEX_BAD=1; I=$N; return 0 ;; esac
         seg="${rest%%\}*}"
         w+="$seg}"; I=$((I + ${#seg} + 1)) ;;
    "'") if [ -n "$1" ]; then w+='$'; I=$((I + 1)); return 0; fi
         I=$((I + 2)); w+='$'
         while (( I < N )); do
           (( STEPS-- > 0 )) || { over_budget; return 0; }
           case "${S:I:1}" in
             '\') I=$((I + 2)) ;;
             "'") I=$((I + 1)); return 0 ;;
             *) I=$((I + 1)) ;;
           esac
         done
         LEX_BAD=1 ;;
    *) w+='$'; I=$((I + 1)) ;;
  esac
}

read_backtick() {
  local j=$((I + 1)) start=$((I + 1)) CWD="$CWD" CWD_OK="$CWD_OK"
  while (( j < N )); do
    (( STEPS-- > 0 )) || { over_budget; return 0; }
    case "${S:j:1}" in
      '\') j=$((j + 2)) ;;
      '`') I=$((j + 1)); w+='`'; has=1
           lex_string "${S:start:j-start}"
           return 0 ;;
      *) j=$((j + 1)) ;;
    esac
  done
  LEX_BAD=1; I=$N
}

# ---------------- main ----------------

[ -z "$HOOK_INPUT" ] && exit 0

# Fail closed: input we can't read is a command we can't check.
if ! CMD="$(json_get '.tool_input.command')"; then
  block "can't parse the hook input, so this command can't be checked. If jq and python3 are missing or broken, install jq."
fi
[ -n "$CMD" ] || block "the hook input names no command, so it can't be checked."
CWD="$(json_get '.cwd')"; CWD="${CWD:-$PWD}"

# Bytes, not characters: ${S:I:1} would count multibyte characters from the start on every call.
LC_ALL=C
STEPS=$((LEX_WORK / ${#CMD}))
lex_string "$CMD"
exit 0
