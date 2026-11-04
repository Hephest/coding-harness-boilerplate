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

# path_policy <path> <cwd> : POLICY + CONTRACT invariants for one write. Every way of writing a file
# (Edit, Write, a shell redirect) comes through here. Relative paths resolve against <cwd>, the
# hook's .cwd, never $PWD. Returns 0 = allowed, 2 = blocked with the reason on stderr.
path_policy() {
  local file="$1" cwd="${2:-$PWD}" dir root rel branch task zone g contract targets glob zprefix gprefix
  case "$file" in /*) ;; *) file="$cwd/$file" ;; esac

  # Canonical form, so a path through a symlink gets the same checks as the real one.
  file="$(canon_path "$file")"

  # 0. Git internals. Matched on the full path: inside .git there is no work tree, so repo_root
  #    finds nothing, and a worktree's .git is a file that points into the main repo's .git.
  case "$file" in
    */.git|*/.git/*)
      echo "BLOCKED: '$file' is a protected path (git internals)." >&2; return 2 ;;
  esac

  dir="$(dirname "$file")"; while [ ! -d "$dir" ]; do dir="$(dirname "$dir")"; done
  if ! root="$(repo_root_checked "$dir")"; then
    echo "BLOCKED: git is missing or failing here, so '$file' can't be checked. Install git or fix the repo." >&2
    return 2
  fi
  [ -z "$root" ] && return 0                     # not a git repo: nothing to guard
  rel="${file#"$root"/}"

  # 1. Blast radius: never touch secrets or local permission overrides, at any depth in the tree.
  #    These stay blocked even in maintainer mode.
  case "$rel" in
    .env|.env.*|*/.env|*/.env.*|secrets/*|*.pem|*.key|*.p12|*.pfx|id_rsa*|*/id_rsa*|.npmrc|*/.npmrc|.netrc|*/.netrc)
      echo "BLOCKED: '$rel' is a protected path (secrets)." >&2; return 2 ;;
    .claude/settings.local.json)
      echo "BLOCKED: '$rel' holds local permission overrides. Only the user edits it." >&2; return 2 ;;
  esac

  # 1b. The harness's own sensors and policy are human-owned. Maintainers of this boilerplate
  #     start Claude with HARNESS_MAINTAINER=1 to edit them (contract scope still applies below).
  #     Root CLAUDE.md and .claude/rules/* shape behaviour as much as a hook does. A module's own
  #     CLAUDE.md stays writable, and .agent/lessons.md too: /finish appends to it.
  case "$rel" in
    CLAUDE.md|.claude/rules/*|.claude/hooks/*|.claude/settings.json|.claude/protected-paths|.claude/agents/*|.claude/skills/*|.claude/commands/*|scripts/verify.sh|scripts/herdr-sub.sh|scripts/harness-init.sh|tests/harness/*)
      if [ "${HARNESS_MAINTAINER:-}" != 1 ]; then
        echo "BLOCKED: '$rel' is harness infrastructure. Propose the change to the user instead of editing it." >&2; return 2
      fi ;;
  esac

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

  # 4. Contract scope: if a task is active, only its target files may change.
  task="$(active_task "$root")"

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

  # Target globs = bullet lines under "## Target files" until the next heading.
  targets="$(awk '/^## Target files/{f=1;next} /^## /{f=0} f && /^- /{sub(/^- +/,""); gsub(/`/,""); print}' "$contract")"
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
