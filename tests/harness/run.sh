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
aux="$(cd "$(mktemp -d)" && pwd -P)"  # outside the fixture: symlinks to it, stub PATH dirs
trap 'rm -rf "$fx" "$aux"' EXIT
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

# guard_raw <expected-exit> <name> <PATH for the hook> <raw stdin> [text stderr must contain]
# $BASH is absolute: `env bash` in the shebang can't work with a stripped PATH.
guard_raw() {
  local want="$1" name="$2" path="$3" input="$4" needle="${5:-}" err got
  err="$( unset HARNESS_MAINTAINER HARNESS_ROLE
          printf '%s' "$input" | PATH="$path" "$BASH" "$fx/.claude/hooks/guard-write.sh" 2>&1 >/dev/null )"
  got=$?
  if [ "$got" != "$want" ]; then bad "guard: $name (want exit $want, got $got)"
  elif [ -n "$needle" ] && [[ "$err" != *"$needle"* ]]; then bad "guard: $name (stderr lacks '$needle': $err)"
  else ok "guard: $name"; fi
}

# On main
guard 2 "main blocked"                  "$fx/src/app.py"
guard 0 "agent dir on main"             "$fx/.agent/contracts/demo.md"
guard 2 "secrets on main"               "$fx/.env"

# Git internals (repo_root finds nothing inside .git; a worktree's .git is a file)
guard 2 "git internals: config"         "$fx/.git/config"
guard 2 "git internals: worktree gitdir" "$fx/.git/worktrees/demo/HEAD"
guard 2 "git internals: worktree link"  "$wt/.git"
guard 2 "git internals: maintainer"     "$fx/.git/config" maint
guard 0 "git internals: .github is fine" "$wt/.github/workflows/ci.yml"

# Detached HEAD behaves like main
g "$fx" worktree add -q --detach "$fx/.worktrees/detached" HEAD
guard 2 "detached head"                 "$fx/.worktrees/detached/src/app.py"
guard 0 "detached head: agent dir"      "$fx/.worktrees/detached/.agent/contracts/demo.md"

# In a task worktree, no active task
guard 0 "worktree allowed"              "$wt/src/app.py"
guard 2 "infra blocked"                 "$wt/.claude/hooks/guard-write.sh"
guard 2 "infra blocked (verify.sh)"     "$wt/scripts/verify.sh"
guard 0 "maintainer infra"              "$wt/.claude/hooks/guard-write.sh" maint
guard 2 "maintainer still blocks local settings" "$wt/.claude/settings.local.json" maint
guard 2 "maintainer still blocks secrets"        "$wt/.env" maint
guard 2 "danger zone without contract"  "$wt/src/billing/pay.py"

# Self-test and slash commands are harness infrastructure
guard 2 "self-test protected"           "$wt/tests/harness/run.sh"
guard 2 "self-test protected: commands" "$wt/.claude/commands/finish.md"
guard 0 "self-test protected: maintainer" "$wt/tests/harness/run.sh" maint
guard 0 "self-test protected: other tests" "$wt/tests/test_app.py"

# Secrets anywhere in the tree, also in maintainer mode
for s in src/.env src/.env.local a/b/.env.prod certs/client.p12 certs/client.pfx \
         id_rsa home/id_rsa home/id_rsa.pub .npmrc web/.npmrc .netrc home/.netrc; do
  guard 2 "nested secrets: $s" "$wt/$s"
done
guard 2 "nested secrets: maintainer"    "$wt/src/.env" maint
guard 0 "nested secrets: lookalike"     "$wt/src/envelope.py"

# Project reached through a symlink: same checks as the real path
ln -s "$wt" "$aux/linked"
ln -s "$fx" "$aux/linked-main"
guard 2 "symlinked root: secrets"       "$aux/linked/.env"
guard 2 "symlinked root: new subdir"    "$aux/linked/new/dir/.env"
guard 2 "symlinked root: danger zone"   "$aux/linked/src/billing/pay.py"
guard 2 "symlinked root: infra"         "$aux/linked/.claude/hooks/guard-write.sh"
guard 2 "symlinked root: main"          "$aux/linked-main/src/app.py"
guard 0 "symlinked root: plain file"    "$aux/linked/src/app.py"
# Symlinks inside the tree, and `..` through a directory that doesn't exist yet
ln -s ../.claude/hooks "$wt/src/hooks-link"
ln -s ../.env "$wt/src/env-link"
guard 2 "symlinked dir into infra"      "$wt/src/hooks-link/guard-write.sh"
guard 2 "symlinked file to secrets"     "$wt/src/env-link"
guard 2 "dotdot through missing dir"    "$wt/src/nope/../../.claude/hooks/guard-write.sh"

# Fail closed: input that can't be parsed blocks the write
tool_dir() { # tool_dir <name> <tool...> : a PATH dir holding only these tools, no jq, no python3
  local d="$aux/$1" t; shift; mkdir -p "$d"
  for t in "$@"; do ln -s "$(command -v "$t")" "$d/$t"; done
  echo "$d"
}
input() { printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$1"; }
bare="$(tool_dir bare cat dirname)"
broken="$(tool_dir broken cat dirname)"
printf '#!/bin/sh\nexit 1\n' > "$broken/python3"; chmod +x "$broken/python3"
guard_raw 2 "fail closed: no jq, no python3" "$bare"   "$(input "$wt/src/app.py")" "install jq"
guard_raw 2 "fail closed: broken python3"    "$broken" "$(input "$wt/src/app.py")" "install jq"
guard_raw 2 "fail closed: malformed input"   "$PATH"   '{"tool_input":'            "install jq"
guard_raw 0 "fail closed: empty input"       "$bare"   ""
if command -v python3 >/dev/null 2>&1; then
  py="$(tool_dir py cat dirname git python3)"
  guard_raw 0 "python fallback: allowed"     "$py" "$(input "$wt/src/app.py")"
  guard_raw 2 "python fallback: blocked"     "$py" "$(input "$wt/.env")" "protected path"
else
  echo "SKIP  python fallback (python3 not installed)"
fi

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
guard 0 "symlinked root: contract target"  "$aux/linked/src/app.py"
guard 2 "symlinked root: contract outside" "$aux/linked/src/other.py"
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

# ---------------- 5. hygiene (maintainers of this boilerplate only) ----------------
# Tracked files ship to template users, so nothing from a maintainer's machine may leak into them.
# The patterns are split so this file doesn't match itself.
if [ "${HARNESS_MAINTAINER:-}" = 1 ]; then
  hits="$( git -C "$ROOT" grep -nIiE 'acade''mos|heph''est' -- .; git -C "$ROOT" grep -nIE '/Use''rs/' -- . )"
  if [ -z "$hits" ]; then ok "hygiene: no personal strings in tracked files"
  else bad "hygiene: personal strings in tracked files"; printf '%s\n' "$hits" | sed 's/^/      /'; fi
else
  echo "SKIP  hygiene (HARNESS_MAINTAINER unset)"
fi

echo "=== harness self-test: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
