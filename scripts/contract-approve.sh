#!/usr/bin/env bash
# Records a human's approval of a contract, so the guard lets work start on it.
#   scripts/contract-approve.sh <task-id>
#
# Run it from the checkout that holds the contract: the main checkout before the worktree exists,
# or the worktree after an edit. The hash goes under the git common dir, shared by every worktree.
# The agent can't run this: the guard and settings.json both refuse it. The guard asks you to,
# with `! scripts/contract-approve.sh <task-id>`. If that is refused too, use a plain terminal.
set -uo pipefail

die() { echo "contract-approve: $1" >&2; exit 1; }

[ $# -eq 1 ] || { echo "usage: ${0##*/} <task-id>" >&2; exit 2; }
id="$1"
case "$id" in
  ''|.*|-*|*[!A-Za-z0-9._-]*) die "'$id' is not a task id." ;;
esac

# shellcheck source=../.claude/hooks/_lib.sh
. "$(cd "$(dirname "$0")/.." && pwd -P)/.claude/hooks/_lib.sh"

root="$(repo_root .)" && [ -n "$root" ] || die "not inside a git checkout."
contract="$root/.agent/contracts/$id.md"
[ -f "$contract" ] || die "no contract at $contract"

# A placeholder left from TEMPLATE.md means the contract was never filled in. Code spans are taken
# out first: a real contract can quote `<id>`, but the template's <test name> is one of them.
text="$(sed -e 's/<!--.*-->//' -e 's/`<test name>`/<test name>/' -e 's/`[^`]*`//g' "$contract")"
left="$(printf '%s\n' "$text" | grep -nE '<(task-id|what changes and why|path|file|observable behaviour|test name|things the agent[^>]*|schema rules[^>]*)>')"
[ -z "$left" ] || die "$id.md still holds template placeholders:
$left"

targets="$(contract_targets "$contract")"
count="$(printf '%s\n' "$targets" | grep -c .)"
[ "$count" -le 5 ] || die "$id.md lists $count target files, the limit is 5. Split the task."

hash="$(sha256_of "$contract")" || die "neither shasum nor sha256sum is installed, so nothing can be approved."
record="$(approval_file "$root" "$id")" || die "can't find the git common dir."

echo "Contract: $contract"
echo
echo "Target files:"
printf '%s\n' "$targets" | sed 's/^/  /'
echo
echo "Acceptance criteria:"
awk '/^## Acceptance criteria/{f=1;next} /^## /{f=0} f && !/^<!--/ && NF' "$contract" | sed 's/^/  /'
echo

mkdir -p "$(dirname "$record")" || die "can't create $(dirname "$record")"
printf '%s\n' "$hash" > "$record" || die "can't write $record"
echo "Approved '$id' (sha256 $hash)."
echo "Any edit to the contract needs a fresh approval."
