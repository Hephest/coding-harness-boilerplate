#!/usr/bin/env bash
# Harness self-test: checks that the hooks and verify.sh still enforce what the docs promise.
#   tests/harness/run.sh        exit 0 = every check passed
#
# 1. Syntax: bash -n on every harness shell script (+ shellcheck if it is installed).
# 2. Behaviour: builds a throwaway git repo, copies the hooks into it, feeds them the same JSON
#    Claude Code sends, and asserts the exit codes (2 = blocked, 0 = allowed).
# Needs: bash, git, and jq or python3 (same as the hooks). Never touches the real repo.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS  $1"; }
bad() { fail=$((fail + 1)); echo "FAIL  $1"; }

# ---------------- 1. syntax ----------------
scripts=()
for f in "$ROOT"/.claude/hooks/*.sh "$ROOT"/scripts/*.sh "$ROOT"/tests/harness/*.sh "$ROOT"/.githooks/*; do
  [ -f "$f" ] && scripts+=("$f")
done
for f in "${scripts[@]}"; do
  if out="$(bash -n "$f" 2>&1)"; then ok "bash -n ${f#"$ROOT"/}"; else bad "bash -n ${f#"$ROOT"/}: $out"; fi
done
if command -v shellcheck >/dev/null 2>&1; then
  # -x follows the `. _lib.sh` source; severity error keeps style nits out of the gate.
  if out="$(cd "$ROOT" && shellcheck -x -S error "${scripts[@]}" 2>&1)"; then ok "shellcheck"; else bad "shellcheck"; printf '%s\n' "$out" | sed 's/^/      /'; fi
else
  echo "SKIP  shellcheck (not installed)"
fi

# ---------------- 2. fixture repo ----------------
fx="$(cd "$(mktemp -d)" && pwd -P)"   # pwd -P: /var → /private/var on macOS, same as git reports
trap 'rm -rf "$fx"' EXIT
g() { git -C "$1" -c user.name=harness -c user.email=harness@example.invalid -c commit.gpgsign=false "${@:2}"; }

mkdir -p "$fx/.claude" "$fx/scripts" "$fx/.agent/state" "$fx/.agent/contracts" "$fx/src/billing"
cp -R "$ROOT/.claude/hooks" "$fx/.claude/hooks"
cp "$ROOT/scripts/verify.sh" "$fx/scripts/verify.sh"
cp "$ROOT/.gitignore" "$fx/.gitignore"
touch "$fx/.agent/state/.gitkeep"
printf '# danger zones\nsrc/billing/*\n' > "$fx/.claude/protected-paths"
echo 'print("hi")' > "$fx/src/app.py"
g "$fx" init -q && g "$fx" symbolic-ref HEAD refs/heads/main
g "$fx" add -A && g "$fx" commit -qm "fixture"
g "$fx" worktree add -q -b task/demo "$fx/.worktrees/demo" HEAD
wt="$fx/.worktrees/demo"

# guard <expected-exit> <name> <file> [maintainer]
guard() {
  local want="$1" name="$2" file="$3" maint="${4:-}" got
  got="$( unset HARNESS_MAINTAINER HARNESS_ROLE
          [ -n "$maint" ] && export HARNESS_MAINTAINER=1
          printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$file" \
            | "$fx/.claude/hooks/guard-write.sh" >/dev/null 2>&1; echo $? )"
  if [ "$got" = "$want" ]; then ok "guard: $name"; else bad "guard: $name (want exit $want, got $got)"; fi
}

# On main
guard 2 "main blocked"                  "$fx/src/app.py"
guard 0 "agent dir on main"             "$fx/.agent/contracts/demo.md"
guard 2 "secrets on main"               "$fx/.env"

# In a task worktree, no active task
guard 0 "worktree allowed"              "$wt/src/app.py"
guard 2 "infra blocked"                 "$wt/.claude/hooks/guard-write.sh"
guard 2 "infra blocked (verify.sh)"     "$wt/scripts/verify.sh"
guard 0 "maintainer infra"              "$wt/.claude/hooks/guard-write.sh" maint
guard 2 "maintainer still blocks local settings" "$wt/.claude/settings.local.json" maint
guard 2 "maintainer still blocks secrets"        "$wt/.env" maint
guard 2 "danger zone without contract"  "$wt/src/billing/pay.py"

# Active task with a contract
mkdir -p "$wt/.agent/state" "$wt/.agent/contracts"
cat > "$wt/.agent/contracts/demo.md" <<'EOF'
# Contract: demo
## Target files
- src/app.py
- `src/billing/*`
## Acceptance criteria
1. x
EOF
echo demo > "$wt/.agent/state/active-task"
guard 0 "contract scope: target"        "$wt/src/app.py"
guard 2 "contract scope: outside"       "$wt/src/other.py"
guard 0 "danger zone named in contract" "$wt/src/billing/pay.py"
printf '# Contract: demo\n## Target files\n- src/*\n' > "$wt/.agent/contracts/demo.md"
guard 2 "danger zone needs specific glob" "$wt/src/billing/pay.py"
echo ghost > "$wt/.agent/state/active-task"
guard 2 "active task without contract"  "$wt/src/app.py"
rm -f "$wt/.agent/state/active-task"

# ---------------- 3. verify.sh ----------------
code="$( unset HARNESS_MAINTAINER; "$fx/scripts/verify.sh" >/dev/null 2>&1; echo $? )"
[ "$code" = 78 ] && ok "verify: no sensors exits 78" || bad "verify: no sensors exits 78 (got $code)"
code="$( export HARNESS_MAINTAINER=1; "$fx/scripts/verify.sh" >/dev/null 2>&1; echo $? )"
[ "$code" = 78 ] && ok "verify: maintainer without self-test still 78" || bad "verify: maintainer without self-test still 78 (got $code)"

# ---------------- 4. .gitignore ----------------
if g "$fx" check-ignore -q .agent/state/.gitkeep; then bad "gitignore: .gitkeep is ignored"; else ok "gitignore: .gitkeep tracked"; fi
if g "$fx" check-ignore -q .agent/state/active-task; then ok "gitignore: run state ignored"; else bad "gitignore: run state ignored"; fi

echo "=== harness self-test: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
