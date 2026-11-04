#!/usr/bin/env bash
# PreToolUse (Edit|Write|MultiEdit|NotebookEdit): reads the path, path_policy in _lib.sh decides.
# Exit 2 blocks the write and shows stderr to Claude.
set -uo pipefail
HOOK_INPUT="$(cat)"
. "$(dirname "$0")/_lib.sh"

[ -z "$HOOK_INPUT" ] && exit 0

# Fail closed: input we can't read is a write we can't check.
if ! file="$(hook_path)"; then
  echo "BLOCKED: can't parse the hook input, so this write can't be checked. If jq and python3 are missing or broken, install jq." >&2
  exit 2
fi
if [ -z "$file" ]; then
  echo "BLOCKED: the hook input names no file, so this write can't be checked." >&2
  exit 2
fi

cwd="$(json_get '.cwd')"
path_policy "$file" "${cwd:-$PWD}"
