#!/usr/bin/env bash
# PostToolUse (Edit|Write|MultiEdit|NotebookEdit): fast SENSOR on the file just written.
# Exit 2 sends stderr back to Claude so it fixes the error now, not 15 steps later.
set -uo pipefail
HOOK_INPUT="$(cat)"
. "$(dirname "$0")/_lib.sh"

file="$(hook_path)"
[ -z "$file" ] && exit 0
case "$file" in
  /*) ;;
  *) cwd="$(json_get '.cwd')"; file="${cwd:-$PWD}/$file" ;;
esac
[ ! -f "$file" ] && exit 0
root="$(repo_root "$(dirname "$file")")"
[ -z "$root" ] || [ ! -x "$root/scripts/verify.sh" ] && exit 0

out="$("$root/scripts/verify.sh" --fast "$file" 2>&1)"; code=$?
if [ $code -ne 0 ]; then
  echo "SENSOR FAILED on $file (exit $code). Fix before continuing:" >&2
  printf '%s\n' "$out" | tail -n 30 >&2
  exit 2
fi
exit 0
