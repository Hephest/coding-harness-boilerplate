#!/usr/bin/env bash
# Shared helpers for hooks. Hooks receive a JSON event on stdin.

# json_get '.a.b' : reads $HOOK_INPUT, prints the value or empty.
# Returns non-zero when the input can't be parsed (malformed, or no jq and no working python3).
json_get() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$HOOK_INPUT" | jq -r "$1 // empty" 2>/dev/null
  else
    printf '%s' "$HOOK_INPUT" | python3 -c '
import json, sys
d = json.load(sys.stdin)
cur = d
for k in sys.argv[1].lstrip(".").split("."):
    cur = cur.get(k) if isinstance(cur, dict) else None
print("" if cur is None else cur)
' "$1" 2>/dev/null
  fi
}

# hook_path : the path the tool is about to touch. Two reads, not jq's `//`: the python fallback
# can't do alternatives, and NotebookEdit names its file notebook_path, not file_path.
# Returns non-zero when the input can't be parsed, same as json_get.
hook_path() {
  local p
  p="$(json_get '.tool_input.file_path')" || return 1
  if [ -z "$p" ]; then p="$(json_get '.tool_input.notebook_path')" || return 1; fi
  printf '%s\n' "$p"
}

# canon_path <path> [hops] : physical absolute path, the form git reports for the repo root.
# Walks one component at a time so it also works for files and directories that don't exist yet.
# Follows symlinks in directories and at the leaf; `..` is applied after each symlink is resolved.
canon_path() {
  local p="$1" hops="${2:-0}" cur="" part link parts
  case "$p" in /*) ;; *) p="$PWD/$p" ;; esac
  IFS=/ read -r -d '' -a parts < <(printf '%s\0' "$p")
  for part in "${parts[@]}"; do
    case "$part" in
      ''|.) ;;
      ..) cur="${cur%/*}" ;;
      *) if [ -d "$cur/$part" ]; then
           cur="$(cd -P "$cur/$part" 2>/dev/null && pwd -P)" || cur="$cur/$part"
         else
           cur="$cur/$part"
         fi ;;
    esac
  done
  if [ -L "$cur" ] && [ "$hops" -lt 16 ]; then
    link="$(readlink "$cur")"
    case "$link" in /*) ;; *) link="${cur%/*}/$link" ;; esac
    canon_path "$link" "$((hops + 1))"; return
  fi
  printf '%s\n' "$cur"
}

# repo_root <dir> : git toplevel for a dir (works inside worktrees)
repo_root() { git -C "$1" rev-parse --show-toplevel 2>/dev/null; }

# repo_root_checked <dir> : repo_root that tells "no repo here" from "can't tell". Prints the root,
# or nothing when git itself says this is not a repo. Returns non-zero when git is missing or
# refuses (broken, dubious ownership): then an empty answer would wave the write through unchecked.
repo_root_checked() {
  local root err
  if root="$(repo_root "$1")"; then printf '%s\n' "$root"; return 0; fi
  err="$(LC_ALL=C git -C "$1" rev-parse --show-toplevel 2>&1 >/dev/null)"
  case "$err" in *'not a git repository'*) return 0 ;; esac
  return 1
}

# active_task <root> : task id from .agent/state/active-task, or empty
active_task() { [ -f "$1/.agent/state/active-task" ] && tr -d '[:space:]' < "$1/.agent/state/active-task"; }

# is_secret <rel> : true for a repo-relative path on the secrets list, at any depth in the tree.
is_secret() {
  case "$1" in
    .env|.env.*|*/.env|*/.env.*|secrets/*|*.pem|*.key|*.p12|*.pfx|id_rsa*|*/id_rsa*|.npmrc|*/.npmrc|.netrc|*/.netrc) return 0 ;;
  esac
  return 1
}

# is_harness <rel> : true for a repo-relative path the user owns, or a directory that holds one.
# Files directly under .claude all configure the harness. Its other subdirectories are tool state.
is_harness() {
  case "$1" in
    CLAUDE.md|scripts|tests|.claude/rules/*|.claude/hooks/*|.claude/agents/*|.claude/skills/*|.claude/commands/*|scripts/verify.sh|scripts/herdr-sub.sh|scripts/harness-init.sh|scripts/contract-approve.sh|tests/harness/*) return 0 ;;
    .claude/*/*) return 1 ;;
    .claude/*) return 0 ;;
  esac
  return 1
}

# contract_targets <contract> : bullet lines under "## Target files", until the next heading. Plain
# bash: every write on a task with a contract comes through here, and needing awk would block them.
contract_targets() {
  local line f=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '## Target files'*) f=1 ;;
      '## '*) f=0 ;;
      '- '*) [ "$f" = 1 ] || continue
             line="${line#- }"; line="${line#"${line%%[! ]*}"}"
             printf '%s\n' "${line//\`/}" ;;
    esac
  done < "$1"
}

# sha256_of <file> : the hash, or non-zero when no tool can make one. Read from stdin, because
# sha256sum escapes an awkward file name and marks the hash for it.
sha256_of() {
  local h=""
  if command -v shasum >/dev/null 2>&1; then read -r h _ < <(shasum -a 256 < "$1")
  elif command -v sha256sum >/dev/null 2>&1; then read -r h _ < <(sha256sum < "$1")
  fi
  [ -n "$h" ] && printf '%s\n' "$h"
}

# approval_file <root> <id> : where a contract's approved hash lives. Under the git common dir, so
# every worktree shares it, and under .git, so both guards already protect it.
approval_file() {
  local common
  common="$(git -C "$1" rev-parse --git-common-dir 2>/dev/null)" && [ -n "$common" ] || return 1
  case "$common" in /*) ;; *) common="$1/$common" ;; esac
  printf '%s/harness/approved/%s.sha256\n' "$common" "$2"
}

# approval_hint <root> <id> : what to do about a blocked approval.
approval_hint() {
  echo "Show the user .agent/contracts/$2.md and ask them to run:" >&2
  echo "  ! scripts/contract-approve.sh $2" >&2
  echo "or, in a plain terminal:" >&2
  echo "  cd $1 && scripts/contract-approve.sh $2" >&2
  echo "Everything under .agent/ stays writable, so the contract can still be fixed." >&2
}

# effective_task <root> <branch> : sets TASK_ID to the one id that drives approval and scope, empty
# for no task, and TASK_RECORD to where its approval lives, empty when git can't say. On task/<id>
# with a contract or an approval record that is <id>, whatever active-task says: the agent can
# rewrite that file, so it can't be what picks the rules. Any other branch, and a task branch with
# neither, goes by active-task. Worked out once per checkout per hook run.
effective_task() {
  local root="$1" branch="$2" id="" record=""
  [ "${TASK_FOR:-}" = "$root:$branch" ] && return 0
  case "$branch" in
    task/*) id="${branch#task/}"
            # No common dir: the id stays, so approval_policy blocks instead of guessing.
            if record="$(approval_file "$root" "$id")" \
               && [ ! -f "$record" ] && [ ! -f "$root/.agent/contracts/$id.md" ]; then
              id=""
            fi ;;
  esac
  if [ -z "$id" ]; then
    id="$(active_task "$root")"
    record=""
    if [ -n "$id" ]; then record="$(approval_file "$root" "$id")"; fi
  fi
  TASK_ID="$id"; TASK_RECORD="$record"; TASK_FOR="$root:$branch"
}

# approval_policy <root> <id> <record> : the contract for this work must be the one a human
# approved. Both come from effective_task, so blanking active-task doesn't skip this. An approval
# outlives its contract, so deleting the contract doesn't either. The contract is read from the
# checkout being written to. One pass per hook run: the contract doesn't change while a command is
# being checked.
approval_policy() {
  local root="$1" id="$2" record="$3" contract want="" got
  [ -n "$id" ] || return 0
  [ "${APPROVAL_PASSED:-}" = "$root:$id" ] && return 0
  if [ -z "$record" ]; then
    echo "BLOCKED: git can't name its common dir here, so the contract for '$id' can't be checked." >&2
    return 2
  fi
  contract="$root/.agent/contracts/$id.md"
  [ -f "$contract" ] || [ -f "$record" ] || return 0
  if [ ! -f "$contract" ]; then
    echo "BLOCKED: '$id' was approved, but .agent/contracts/$id.md is missing here. Restore it." >&2
    approval_hint "$root" "$id"; return 2
  fi
  if [ ! -f "$record" ]; then
    echo "BLOCKED: the contract for '$id' isn't approved." >&2
    approval_hint "$root" "$id"; return 2
  fi
  if ! got="$(sha256_of "$contract")"; then
    echo "BLOCKED: neither shasum nor sha256sum is installed, so the sha256 of the contract for '$id' can't be checked." >&2
    return 2
  fi
  IFS= read -r want < "$record"
  if [ "$got" != "$want" ]; then
    echo "BLOCKED: the contract for '$id' changed since it was approved." >&2
    approval_hint "$root" "$id"; return 2
  fi
  APPROVAL_PASSED="$root:$id"
}

# holds_repo <dir, with a trailing slash> <cwd> : true when the repo around <cwd> is under the dir.
holds_repo() {
  local root
  root="$(repo_root "$2")"
  [ -n "$root" ] && case "$root/" in "$1"*) true ;; *) false ;; esac
}

# path_policy <path> <cwd> [parent] : POLICY + CONTRACT invariants for one write. Every way of
# writing a file (Edit, Write, a shell redirect) comes through here. Relative paths resolve against
# <cwd>, the hook's .cwd, never $PWD. With "parent", stops after the protected paths: for a
# directory that something lands in, where the branch and the contract judge the file, not the
# directory. Returns 0 = allowed, 2 = blocked with the reason on stderr.
path_policy() {
  local file="$1" cwd="${2:-$PWD}" scope="${3:-}" dir root rel branch task zone g contract targets glob zprefix gprefix under
  case "$file" in /*) ;; *) file="$cwd/$file" ;; esac

  # Canonical form, so a path through a symlink gets the same checks as the real one.
  # canon_path prints nothing for /.
  file="$(canon_path "$file")"; file="${file:-/}"

  # 0. Git internals. Matched on the full path: inside .git there is no work tree, so repo_root
  #    finds nothing, and a worktree's .git is a file that points into the main repo's .git.
  case "$file" in
    */.git|*/.git/*)
      echo "BLOCKED: '$file' is a protected path (git internals)." >&2; return 2 ;;
  esac

  # 0b. A directory that holds a .git, or holds the repo we're working in, holds everything below
  #     it, secrets included. Holds in maintainer mode, like .git itself. HOOK_CWD is where a shell
  #     command started: after `cd /tmp`, <cwd> alone no longer knows which repo that was.
  if [ -d "$file" ]; then
    # Built first: on bash 5.2 a quoted expansion that strips to empty, right before /*, never matches.
    under="${file%/}/"
    if [ -e "$file/.git" ] || holds_repo "$under" "$cwd" \
       || { [ -n "${HOOK_CWD:-}" ] && [ "$HOOK_CWD" != "$cwd" ] && holds_repo "$under" "$HOOK_CWD"; }; then
      echo "BLOCKED: '$file' holds a whole repository, .git included. Name the paths inside it instead." >&2; return 2
    fi
  fi

  dir="$(dirname "$file")"; while [ ! -d "$dir" ]; do dir="$(dirname "$dir")"; done
  if ! root="$(repo_root_checked "$dir")"; then
    echo "BLOCKED: git is missing or failing here, so '$file' can't be checked. Install git or fix the repo." >&2
    return 2
  fi
  [ -z "$root" ] && return 0                     # not a git repo: nothing to guard
  rel="${file#"$root"/}"

  # 1. Blast radius: never touch secrets or local permission overrides, at any depth in the tree.
  #    These stay blocked even in maintainer mode. The /_ is what's under a directory: a parent of
  #    a protected path counts as that path, so `mv secrets x` is no way around it.
  if is_secret "$rel" || is_secret "$rel/_"; then
    echo "BLOCKED: '$rel' is a protected path (secrets)." >&2; return 2
  fi
  case "$rel" in
    .claude/settings.local.json)
      echo "BLOCKED: '$rel' holds local permission overrides. Only the user edits it." >&2; return 2 ;;
  esac

  # 1b. The harness's own sensors and policy are human-owned. Maintainers of this boilerplate
  #     start Claude with HARNESS_MAINTAINER=1 to edit them (contract scope still applies below).
  #     Root CLAUDE.md and .claude/rules/* shape behaviour as much as a hook does. A module's own
  #     CLAUDE.md stays writable, and .agent/lessons.md too: /finish appends to it.
  if is_harness "$rel" || is_harness "$rel/_"; then
    if [ "${HARNESS_MAINTAINER:-}" != 1 ]; then
      echo "BLOCKED: '$rel' is harness infrastructure. Propose the change to the user instead of editing it." >&2; return 2
    fi
  fi
  [ "$scope" = parent ] && return 0

  # 2. Task bookkeeping (contracts, receipts, lessons) is always writable, also on main,
  #    so /task can write a contract before the worktree exists.
  case "$rel" in .agent/*) return 0 ;; esac

  # 3. Isolation: no edits on the main branch or a detached HEAD (empty name). Work in a worktree.
  branch="$(git -C "$root" branch --show-current 2>/dev/null)"
  if [ -z "$branch" ] || [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
    echo "BLOCKED: you are on ${branch:-a detached HEAD}. Create a worktree first:" >&2
    echo "  git worktree add -b task/<task-id> .worktrees/<task-id> HEAD" >&2
    return 2
  fi

  # 3b. Approval: after the .agent/* exit above, so a blocked agent can still fix its contract.
  effective_task "$root" "$branch"
  task="$TASK_ID"
  approval_policy "$root" "$task" "$TASK_RECORD" || return 2

  # 4. Contract scope: if a task is active, only its target files may change. Same id as above, so
  #    what was approved is what gets enforced.

  # 4a. Danger zones (.claude/protected-paths): need an active contract that names them.
  zone=""
  if [ -f "$root/.claude/protected-paths" ]; then
    while IFS= read -r g; do
      case "$g" in ''|\#*) continue ;; esac
      # shellcheck disable=SC2254
      case "$rel" in $g) zone="$g"; break ;; esac
    done < "$root/.claude/protected-paths"
  fi
  if [ -n "$zone" ] && [ -z "$task" ]; then
    echo "BLOCKED: '$rel' is a danger zone ($zone). Start a task (/task) whose contract lists it under '## Target files'." >&2
    [ -f "$(dirname "$root/$rel")/CLAUDE.md" ] && echo "Read $(dirname "$rel")/CLAUDE.md first." >&2
    return 2
  fi
  [ -z "$task" ] && return 0
  contract="$root/.agent/contracts/$task.md"
  [ -f "$contract" ] || { echo "BLOCKED: active task '$task' has no contract at .agent/contracts/$task.md" >&2; return 2; }

  targets="$(contract_targets "$contract")"
  while IFS= read -r glob; do
    [ -z "$glob" ] && continue
    # A danger-zone file only counts as listed if the glob is at least as specific as the zone
    # (src/auth/*.py lists src/auth/x.py; src/** does not).
    if [ -n "$zone" ]; then
      zprefix="${zone%%\**}"; gprefix="${glob%%\**}"
      case "$gprefix" in "$zprefix"*) ;; *) continue ;; esac
    fi
    # shellcheck disable=SC2254
    case "$rel" in $glob) return 0 ;; esac
  done <<< "$targets"

  if [ -n "$zone" ]; then
    echo "BLOCKED: '$rel' is a danger zone ($zone). The contract for '$task' must name it with a glob at least as specific as '$zone'. Current targets:" >&2
  else
    echo "BLOCKED: '$rel' is outside the contract for '$task'. Allowed:" >&2
  fi
  printf '%s\n' "$targets" | sed 's/^/  /' >&2
  echo "If this file really must change, stop and ask the user to amend the contract." >&2
  return 2
}
