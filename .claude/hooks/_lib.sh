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

# active_task <root> : task id from .agent/state/active-task, or empty
active_task() { [ -f "$1/.agent/state/active-task" ] && tr -d '[:space:]' < "$1/.agent/state/active-task"; }
