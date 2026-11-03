#!/usr/bin/env bash
# Shared helpers for hooks. Hooks receive a JSON event on stdin.

# json_get '<python expression on d>' : reads $HOOK_INPUT, prints the value or empty
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

# repo_root <dir> : git toplevel for a dir (works inside worktrees)
repo_root() { git -C "$1" rev-parse --show-toplevel 2>/dev/null; }

# active_task <root> : task id from .agent/state/active-task, or empty
active_task() { [ -f "$1/.agent/state/active-task" ] && tr -d '[:space:]' < "$1/.agent/state/active-task"; }
