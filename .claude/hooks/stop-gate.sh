#!/usr/bin/env bash
# Stop: VERIFY + STATE + LOOP BREAKER.
# Claude can't finish while there are uncommitted-or-branch changes that fail verify.sh,
# or while the active task has no receipt. Exit 2 = "keep working", reason on stderr.
set -uo pipefail
HOOK_INPUT="$(cat)"
. "$(dirname "$0")/_lib.sh"

# Subagent sessions (started by scripts/herdr-sub.sh) report back; the main agent owns "done".
[ -n "${HARNESS_ROLE:-}" ] && exit 0

cwd="$(json_get '.cwd')"; [ -z "$cwd" ] && cwd="$PWD"
root="$(repo_root "$cwd")"
[ -z "$root" ] && exit 0
state="$root/.agent/state"; mkdir -p "$state"

# Nothing changed vs main and nothing uncommitted: nothing to gate.
base="$(git -C "$root" merge-base HEAD main 2>/dev/null || git -C "$root" merge-base HEAD master 2>/dev/null || echo HEAD)"
if git -C "$root" diff --quiet "$base" -- . ':!.agent' 2>/dev/null \
   && [ -z "$(git -C "$root" status --porcelain -- . ':!.agent' 2>/dev/null)" ]; then
  rm -f "$state/stop-failures"; exit 0
fi

out="$("$root/scripts/verify.sh" 2>&1)"; code=$?

if [ $code -ne 0 ]; then
  sig="$(printf '%s' "$out" | grep -E 'FAIL|Error|error' | head -n 5 | cksum | cut -d' ' -f1)"
  count=$(grep -c "^$sig$" "$state/stop-failures" 2>/dev/null || true)
  echo "$sig" >> "$state/stop-failures"
  if [ "${count:-0}" -ge 2 ]; then
    # Loop breaker: same failure 3 times. Let Claude stop and escalate instead of burning tokens.
    echo "LOOP BREAKER: same verify failure 3 times. Stop, ask 'architect', then report to the user." >&2
    rm -f "$state/stop-failures"
    exit 0
  fi
  echo "NOT DONE: scripts/verify.sh failed (exit $code), attempt $((count + 1))/3. Last lines:" >&2
  printf '%s\n' "$out" | tail -n 30 >&2
  exit 2
fi
rm -f "$state/stop-failures"

task="$(active_task "$root")"
if [ -n "$task" ] && [ ! -f "$root/.agent/receipts/$task.md" ]; then
  echo "NOT DONE: verify passed, but .agent/receipts/$task.md is missing. Run the reviewer, then write the receipt from .agent/receipts/TEMPLATE.md." >&2
  exit 2
fi
exit 0
