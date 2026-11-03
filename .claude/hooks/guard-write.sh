#!/usr/bin/env bash
# PreToolUse (Edit|Write|MultiEdit): POLICY + CONTRACT invariants.
# Exit 2 blocks the write and shows stderr to Claude.
set -uo pipefail
HOOK_INPUT="$(cat)"
. "$(dirname "$0")/_lib.sh"

# Fail closed: input we can't read is a write we can't check.
if ! file="$(json_get '.tool_input.file_path')" && [ -n "$HOOK_INPUT" ]; then
  echo "BLOCKED: can't parse the hook input, so this write can't be checked. If jq and python3 are missing or broken, install jq." >&2
  exit 2
fi
[ -z "$file" ] && exit 0

# Canonical form, so a path through a symlink gets the same checks as the real one.
file="$(canon_path "$file")"

# 0. Git internals. Matched on the full path: inside .git there is no work tree, so repo_root
#    finds nothing, and a worktree's .git is a file that points into the main repo's .git.
case "$file" in
  */.git|*/.git/*)
    echo "BLOCKED: '$file' is a protected path (git internals)." >&2; exit 2 ;;
esac

dir="$(dirname "$file")"; while [ ! -d "$dir" ]; do dir="$(dirname "$dir")"; done
root="$(repo_root "$dir")"
[ -z "$root" ] && exit 0                       # not a git repo: nothing to guard
rel="${file#"$root"/}"

# 1. Blast radius: never touch secrets or local permission overrides, at any depth in the tree.
#    These stay blocked even in maintainer mode.
case "$rel" in
  .env|.env.*|*/.env|*/.env.*|secrets/*|*.pem|*.key|*.p12|*.pfx|id_rsa*|*/id_rsa*|.npmrc|*/.npmrc|.netrc|*/.netrc)
    echo "BLOCKED: '$rel' is a protected path (secrets)." >&2; exit 2 ;;
  .claude/settings.local.json)
    echo "BLOCKED: '$rel' holds local permission overrides. Only the user edits it." >&2; exit 2 ;;
esac

# 1b. The harness's own sensors and policy are human-owned. Maintainers of this boilerplate
#     start Claude with HARNESS_MAINTAINER=1 to edit them (contract scope still applies below).
case "$rel" in
  .claude/hooks/*|.claude/settings.json|.claude/protected-paths|.claude/agents/*|.claude/skills/*|.claude/commands/*|scripts/verify.sh|scripts/herdr-sub.sh|tests/harness/*)
    if [ "${HARNESS_MAINTAINER:-}" != 1 ]; then
      echo "BLOCKED: '$rel' is harness infrastructure. Propose the change to the user instead of editing it." >&2; exit 2
    fi ;;
esac

# 2. Task bookkeeping (contracts, receipts, lessons) is always writable, also on main,
#    so /task can write a contract before the worktree exists.
case "$rel" in .agent/*) exit 0 ;; esac

# 3. Isolation: no edits on the main branch or a detached HEAD (empty name). Work in a worktree.
branch="$(git -C "$root" branch --show-current 2>/dev/null)"
if [ -z "$branch" ] || [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
  echo "BLOCKED: you are on ${branch:-a detached HEAD}. Create a worktree first:" >&2
  echo "  git worktree add -b task/<task-id> .worktrees/<task-id> HEAD" >&2
  exit 2
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
  exit 2
fi
[ -z "$task" ] && exit 0
contract="$root/.agent/contracts/$task.md"
[ -f "$contract" ] || { echo "BLOCKED: active task '$task' has no contract at .agent/contracts/$task.md" >&2; exit 2; }

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
  case "$rel" in $glob) exit 0 ;; esac
done <<< "$targets"

if [ -n "$zone" ]; then
  echo "BLOCKED: '$rel' is a danger zone ($zone). The contract for '$task' must name it with a glob at least as specific as '$zone'. Current targets:" >&2
else
  echo "BLOCKED: '$rel' is outside the contract for '$task'. Allowed:" >&2
fi
printf '%s\n' "$targets" | sed 's/^/  /' >&2
echo "If this file really must change, stop and ask the user to amend the contract." >&2
exit 2
