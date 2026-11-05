#!/usr/bin/env bash
# Stop: VERIFY + STATE + LOOP BREAKER.
# Claude can't finish while there are uncommitted-or-branch changes that fail verify.sh,
# or while the active task has no receipt. Exit 2 = "keep working", reason on stderr.
#
# Every block is bounded, so the gate can't trap a session:
#   - verify exit 78 (no sensors) is a setup gap with nothing to fix in code: it blocks once per
#     session, then allows the stop, and never counts toward the loop breaker.
#   - anything else blocks at most MAX_BLOCKS stops in a row. The count ignores the failure text,
#     which can differ on every run, and stop_hook_active, which is true on all but the first.
set -uo pipefail
HOOK_INPUT="$(cat)"
. "$(dirname "$0")/_lib.sh"

MAX_BLOCKS=3

# Subagent sessions (started by scripts/herdr-sub.sh) report back; the main agent owns "done".
[ -n "${HARNESS_ROLE:-}" ] && exit 0

cwd="$(json_get '.cwd')"; [ -z "$cwd" ] && cwd="$PWD"
root="$(repo_root "$cwd")"
[ -z "$root" ] && exit 0
state="$root/.agent/state"; mkdir -p "$state"

# session_id ends up in a file name, so it can't be allowed to carry a path.
sid="$(json_get '.session_id')"; sid="${sid//[^A-Za-z0-9_-]/_}"; sid="${sid:-unknown}"
blocks="$state/stop-blocks-$sid"
warned="$state/sensors-warned-$sid"

allow() { rm -f "$blocks"; exit 0; }

# block <reason> [details]: exit 2 and count it, or let the stop through once the limit is reached.
# A count that can't be saved can't be bounded, so that lets the stop through as well.
block() {
  local n; n="$(cat "$blocks" 2>/dev/null)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  if [ "$n" -ge "$MAX_BLOCKS" ] || ! { echo "$((n + 1))" > "$blocks"; } 2>/dev/null; then
    echo "LOOP BREAKER: $MAX_BLOCKS blocked stops in a row. Stop, ask 'architect', then report to the user." >&2
    allow
  fi
  n=$((n + 1))
  echo "NOT DONE (blocked stop $n/$MAX_BLOCKS): $1" >&2
  [ -n "${2:-}" ] && printf '%s\n' "$2" | tail -n 30 >&2
  [ "$n" -eq "$MAX_BLOCKS" ] && echo "This is the last block. If it isn't fixed now, ask 'architect' and report to the user." >&2
  exit 2
}

# Nothing changed vs main and nothing uncommitted: nothing to gate.
base="$(git -C "$root" merge-base HEAD main 2>/dev/null || git -C "$root" merge-base HEAD master 2>/dev/null || echo HEAD)"
if git -C "$root" diff --quiet "$base" -- . ':!.agent' 2>/dev/null \
   && [ -z "$(git -C "$root" status --porcelain -- . ':!.agent' 2>/dev/null)" ]; then
  allow
fi

out="$("$root/scripts/verify.sh" 2>&1)"; code=$?

if [ $code -eq 78 ]; then
  [ -e "$warned" ] && allow
  { : > "$warned"; } 2>/dev/null || allow   # can't remember the warning: it would repeat forever
  echo "NOT DONE: scripts/verify.sh found no sensors (exit 78), so this work is unverified. There is nothing to fix in code: tell the user the sensors need setting up. This is shown once per session; the next stop is allowed." >&2
  printf '%s\n' "$out" | tail -n 30 >&2
  exit 2
fi

[ $code -ne 0 ] && block "scripts/verify.sh failed (exit $code). Last lines:" "$out"

# The same id the guard enforces, so blanking active-task doesn't skip the receipt. A task branch
# with neither contract nor record never started a task, so it has nothing to close.
effective_task "$root" "$(git -C "$root" branch --show-current 2>/dev/null)"
task="${TASK_ID:-}"
if task_unstarted "$root"; then task=""; fi
if [ -n "$task" ] && [ ! -f "$root/.agent/receipts/$task.md" ]; then
  block "verify passed, but .agent/receipts/$task.md is missing. Run the reviewer, then write the receipt from .agent/receipts/TEMPLATE.md."
fi
allow
