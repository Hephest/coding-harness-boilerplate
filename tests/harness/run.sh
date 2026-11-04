#!/usr/bin/env bash
# Harness self-test: checks that the hooks and verify.sh still enforce what the docs promise.
#   tests/harness/run.sh        exit 0 = every check passed
#
# 1. Syntax: bash -n on every harness shell script (+ shellcheck if it is installed).
# 2. Behaviour: builds a throwaway git repo, copies the hooks into it, feeds them the same JSON
#    Claude Code sends, and asserts the exit codes (2 = blocked, 0 = allowed).
# Needs: bash, git, and jq or python3 (same as the hooks). Never touches the real repo.
set -uo pipefail

# git exports GIT_DIR/GIT_INDEX_FILE to hooks. Left in place, every `git -C "$fx"` below would
# run against the caller's repo instead of the fixture. Must stay above the first git call.
# shellcheck disable=SC2046
unset $(git rev-parse --local-env-vars)

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
# pwd -P: /var → /private/var on macOS, same as git reports. The -d test matters: if mktemp fails,
# `cd ""` succeeds, and the fixture (and the rm -rf below) would land on the current directory.
tmpd() { local d; d="$(mktemp -d)" && [ -d "$d" ] && cd "$d" && pwd -P; }
fx="$(tmpd)" && aux="$(tmpd)" && sac="$(tmpd)" || { echo "FAIL  mktemp"; exit 1; }
# aux: outside the fixture, for symlinks to it and stub PATH dirs. sac: the "git env leak" victim.
trap 'rm -rf "$fx" "$aux" "$sac"' EXIT
g() { git -C "$1" -c user.name=harness -c user.email=harness@example.invalid -c commit.gpgsign=false "${@:2}"; }

mkdir -p "$fx/.claude" "$fx/scripts" "$fx/.agent/state" "$fx/.agent/contracts" "$fx/src/billing"
cp -R "$ROOT/.claude/hooks" "$fx/.claude/hooks"
cp "$ROOT/scripts/verify.sh" "$fx/scripts/verify.sh"
cp "$ROOT/.gitignore" "$fx/.gitignore"
touch "$fx/.agent/state/.gitkeep"
printf '# danger zones\nsrc/billing/*\n' > "$fx/.claude/protected-paths"
echo 'print("hi")' > "$fx/src/app.py"
g "$fx" init -q
# Second lock after the unset at the top: nothing below may run unless git really means the fixture.
[ "$(g "$fx" rev-parse --absolute-git-dir 2>/dev/null)" = "$fx/.git" ] \
  || { echo "FAIL  fixture is not its own repo, refusing to continue"; exit 1; }
g "$fx" symbolic-ref HEAD refs/heads/main
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

# fast <expected-exit> <name> <PATH for verify.sh> <file> [text output must contain]
fast() {
  local want="$1" name="$2" path="$3" file="$4" needle="${5:-}" out got
  out="$( PATH="$path" "$BASH" "$fx/scripts/verify.sh" --fast "$file" 2>&1 )"
  got=$?
  if [ "$got" != "$want" ]; then bad "json fast check: $name (want exit $want, got $got: $out)"
  elif [ -n "$needle" ] && [[ "$out" != *"$needle"* ]]; then bad "json fast check: $name (output lacks '$needle': $out)"
  else ok "json fast check: $name"; fi
}
printf '{"ok": true}\n' > "$aux/good.json"
printf '{"ok": \n'      > "$aux/bad.json"
vtools=(bash dirname git date sed tail)   # what verify.sh needs, without jq and python3

# A stub jq next to a python3 that always fails: a pass can only have come from jq.
jqdir="$(tool_dir fast-jq "${vtools[@]}")"
printf '#!/bin/sh\necho "$1" > "%s/jq.arg"\ncase "$2" in *good.json) exit 0 ;; *) exit 5 ;; esac\n' "$aux" > "$jqdir/jq"
printf '#!/bin/sh\nexit 1\n' > "$jqdir/python3"
chmod +x "$jqdir/jq" "$jqdir/python3"
fast 0 "jq preferred over python3" "$jqdir" "$aux/good.json"
[ "$(cat "$aux/jq.arg" 2>/dev/null)" = empty ] && ok "json fast check: runs jq empty" || bad "json fast check: runs jq empty"
fast 1 "jq rejects"                "$jqdir" "$aux/bad.json"
if command -v jq >/dev/null 2>&1; then
  fast 0 "real jq: valid"   "$PATH" "$aux/good.json"
  fast 1 "real jq: invalid" "$PATH" "$aux/bad.json"
else
  echo "SKIP  json fast check: real jq (not installed)"
fi
if command -v python3 >/dev/null 2>&1; then
  pydir="$(tool_dir fast-py "${vtools[@]}" python3)"
  fast 0 "python3 fallback: valid"   "$pydir" "$aux/good.json"
  fast 1 "python3 fallback: invalid" "$pydir" "$aux/bad.json"
else
  echo "SKIP  json fast check: python3 fallback (not installed)"
fi
fast 0 "no jq, no python3: warn and skip" "$(tool_dir fast-none "${vtools[@]}")" "$aux/bad.json" "WARN"

# ---------------- 4. stop gate ----------------
# A branch with commits, the shape every finished task ends in.
g "$fx" worktree add -q -b task/stop "$fx/.worktrees/stop" HEAD
st="$fx/.worktrees/stop"
echo 'x = 1' > "$st/src/feature.py"
g "$st" add -A && g "$st" commit -qm "feature"

# stop <expected-exit> <name> <session> [stop_hook_active] [text stderr must contain]
stop() {
  local want="$1" name="$2" sid="$3" active="${4:-false}" needle="${5:-}" err got
  err="$( unset HARNESS_MAINTAINER HARNESS_ROLE
          printf '{"session_id":"%s","cwd":"%s","stop_hook_active":%s}' "$sid" "$st" "$active" \
            | "$st/.claude/hooks/stop-gate.sh" 2>&1 >/dev/null )"
  got=$?
  if [ "$got" != "$want" ]; then bad "stop: $name (want exit $want, got $got: $err)"
  elif [ -n "$needle" ] && [[ "$err" != *"$needle"* ]]; then bad "stop: $name (stderr lacks '$needle': $err)"
  else ok "stop: $name"; fi
}

# 78 once per session: the real verify.sh, the lesson from the versioning-ci session.
stop 2 "78 once per session: first stop blocked"   s78 false "no sensors"
[ -f "$st/.agent/state/sensors-warned-s78" ] && ok "stop: 78 once per session: state file" || bad "stop: 78 once per session: state file"
stop 0 "78 once per session: second stop allowed"  s78 true
stop 0 "78 once per session: stays allowed"        s78 false
stop 2 "78 once per session: new session warned"   s78b
stop 2 "session id can't leave the state dir"      "../../escape"
[ -z "$(find "$st" -name '*escape*' -not -path "$st/.agent/state/*")" ] \
  && ok "stop: session id stays in the state dir" || bad "stop: session id stays in the state dir"

# From here on a stub verify: exit code from a file, and output that differs on every run.
cat > "$st/scripts/verify.sh" <<EOF
#!/usr/bin/env bash
n=\$(( \$(cat "$aux/verify-runs" 2>/dev/null || echo 0) + 1 )); echo "\$n" > "$aux/verify-runs"
echo "FAIL flaky test, run \$n, port \$RANDOM"
exit "\$(cat "$aux/verify-code")"
EOF
verify_exits() { echo "$1" > "$aux/verify-code"; }

# Would be allowed one stop early if the 78 block counted.
verify_exits 1;  stop 2 "78 not counted: failure 1" snc
verify_exits 78; stop 2 "78 not counted: warning"   snc true "no sensors"
verify_exits 1;  stop 2 "78 not counted: failure 2" snc true
                 stop 2 "78 not counted: failure 3" snc true "last block"
                 stop 0 "78 not counted: breaker"   snc true "LOOP BREAKER"
verify_exits 78; stop 2 "78 not counted: alone"     snc2
                 stop 0 "78 not counted: allowed"   snc2 true
[ ! -e "$st/.agent/state/stop-blocks-snc2" ] && ok "stop: 78 not counted: no count kept" || bad "stop: 78 not counted: no count kept"

verify_exits 1
stop 2 "unstable failure output still breaks loop: block 1" sflaky false "blocked stop 1/3"
stop 2 "unstable failure output still breaks loop: block 2" sflaky true  "blocked stop 2/3"
stop 2 "unstable failure output still breaks loop: block 3" sflaky true  "blocked stop 3/3"
stop 0 "unstable failure output still breaks loop: allowed" sflaky true  "LOOP BREAKER"
stop 2 "loop breaker: a new streak starts over"             sflaky false "blocked stop 1/3"
stop 2 "loop breaker: the count is per session"             sother false "blocked stop 1/3"
verify_exits 0
stop 0 "loop breaker: a pass ends the streak"               sflaky true
verify_exits 1
stop 2 "loop breaker: count cleared by the pass"            sflaky false "blocked stop 1/3"

# A count that can't be saved must not turn into an endless block.
mkdir "$st/.agent/state/stop-blocks-sstuck"
stop 0 "loop breaker: unwritable count lets the stop through" sstuck false "LOOP BREAKER"
rmdir "$st/.agent/state/stop-blocks-sstuck"

# The missing-receipt block is bounded by the same breaker.
verify_exits 0
mkdir -p "$st/.agent/receipts"; echo demo > "$st/.agent/state/active-task"
stop 2 "receipt missing: block 1" srcpt false "receipts/demo.md"
stop 2 "receipt missing: block 2" srcpt true
stop 2 "receipt missing: block 3" srcpt true
stop 0 "receipt missing: allowed" srcpt true  "LOOP BREAKER"
stop 2 "receipt missing: streak restarts" srcpt false "receipts/demo.md"
touch "$st/.agent/receipts/demo.md"
stop 0 "receipt written: allowed" srcpt true
rm -f "$st/.agent/state/active-task" "$st/.agent/receipts/demo.md"

# ---------------- 5. settings.json ----------------
settings="$ROOT/.claude/settings.json"
if command -v jq >/dev/null 2>&1; then
  stop_timeout="$(jq -r '.hooks.Stop[].hooks[] | select(.command | contains("stop-gate.sh")) | .timeout' "$settings")"
  denied="$(jq -r '.permissions.deny[]' "$settings")"
  asked="$(jq -r '(.permissions.ask // [])[]' "$settings")"
else
  stop_timeout="$(python3 -c 'import json,sys; print(*[h.get("timeout") for e in json.load(open(sys.argv[1]))["hooks"]["Stop"] for h in e["hooks"] if "stop-gate.sh" in h["command"]])' "$settings")"
  denied="$(python3 -c 'import json,sys; print(*json.load(open(sys.argv[1]))["permissions"]["deny"], sep="\n")' "$settings")"
  asked="$(python3 -c 'import json,sys; print(*json.load(open(sys.argv[1]))["permissions"].get("ask", []), sep="\n")' "$settings")"
fi
[ "$stop_timeout" = 900 ] && ok "settings: stop hook timeout 900" || bad "settings: stop hook timeout 900 (got '$stop_timeout')"
for rule in 'Bash(git add -f:*)' 'Bash(git add --force:*)'; do
  if grep -qxF "$rule" <<< "$denied"; then ok "settings: denies $rule"; else bad "settings: denies $rule"; fi
done
# Deny holds in every mode and has no dialog; ask prompts cleared unattended with nobody answering.
for rule in 'Bash(git push:*)' 'Bash(git reset:*)' 'Bash(rm:*)'; do
  if grep -qxF "$rule" <<< "$denied"; then ok "settings: denies $rule"; else bad "settings: denies $rule"; fi
  if grep -qxF "$rule" <<< "$asked"; then bad "settings: $rule not in ask"; else ok "settings: $rule not in ask"; fi
done

# ---------------- 6. git env leak ----------------
# Incident 2026-11-03: git exported GIT_DIR to the pre-commit hook, the self-test inherited it, and
# its fixture calls hit the real repo: main moved, task/demo appeared, core.bare became true.
# Replayed here against $sac, a throwaway repo. GIT_DIR below must never name anything else.
if [ -n "${HARNESS_SELFTEST_NESTED:-}" ]; then
  echo "SKIP  git env leak (already inside it)"
else
  mkdir -p "$sac/tests/harness"
  # Stands in for the self-test when the hook runs: records the git env the hook handed down.
  cat > "$sac/tests/harness/run.sh" <<'EOF'
#!/usr/bin/env bash
env | grep -E '^GIT_(DIR|INDEX_FILE)=' > "$HOOK_PROBE"
exit 0
EOF
  chmod +x "$sac/tests/harness/run.sh"
  g "$sac" init -q
  g "$sac" symbolic-ref HEAD refs/heads/main
  g "$sac" add -A && g "$sac" commit -qm "sacrificial"
  g "$sac" worktree add -q -b task/hook "$sac/.worktrees/hook" HEAD

  snapshot() {
    echo "HEAD $(cat "$sac/.git/HEAD") $(g "$sac" rev-parse HEAD)"
    g "$sac" for-each-ref
    g "$sac" worktree list --porcelain
    echo "index $(cksum < "$sac/.git/index")"
    echo "core.bare $(g "$sac" config --get core.bare)"
  }
  before="$(snapshot)"
  out="$( HARNESS_SELFTEST_NESTED=1 GIT_DIR="$sac/.git" GIT_INDEX_FILE="$sac/.git/index" \
            "$ROOT/tests/harness/run.sh" 2>&1 )"
  code=$?
  after="$(snapshot)"
  if [ "$code" = 0 ]; then ok "git env leak: self-test passes with a leaked GIT_DIR"
  else bad "git env leak: self-test passes with a leaked GIT_DIR (exit $code)"; printf '%s\n' "$out" | grep -E '^FAIL' | sed 's/^/      /'; fi
  if [ "$before" = "$after" ]; then ok "git env leak: HEAD, refs, index and core.bare unchanged"
  else bad "git env leak: HEAD, refs, index and core.bare unchanged"; diff <(echo "$before") <(echo "$after") | sed 's/^/      /'; fi

  # The hook itself, through a real commit from a linked worktree (that is what exports GIT_DIR).
  # Copied into the throwaway repo's .git/hooks, so core.hooksPath stays unset everywhere.
  mkdir -p "$sac/.git/hooks"
  cp "$ROOT/.githooks/pre-commit" "$sac/.git/hooks/pre-commit"
  HOOK_PROBE="$aux/hook-env" g "$sac/.worktrees/hook" commit -q --allow-empty -m "hook probe"
  if [ ! -f "$aux/hook-env" ]; then bad "git env leak: pre-commit ran the self-test"
  elif [ -s "$aux/hook-env" ]; then bad "git env leak: pre-commit clears git env ($(tr '\n' ' ' < "$aux/hook-env"))"
  else ok "git env leak: pre-commit clears git env"; fi
fi

# ---------------- 7. .gitignore ----------------
if g "$fx" check-ignore -q .agent/state/.gitkeep; then bad "gitignore: .gitkeep is ignored"; else ok "gitignore: .gitkeep tracked"; fi
if g "$fx" check-ignore -q .agent/state/active-task; then ok "gitignore: run state ignored"; else bad "gitignore: run state ignored"; fi

# ---------------- 8. herdr-sub.sh ----------------
# A subagent that loses maintainer mode gets exit 78 from verify.sh, not the self-test. The stub
# herdr strips the caller's value, so a headless subagent only sees what the run script exported.
hs="$(tool_dir herdr-stub)"
cat > "$hs/herdr" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$HERDR_STUB_LOG"
case "$1 $2" in
  "tab create") echo '{"result":{"tab":{"tab_id":"t1"},"root_pane":{"pane_id":"p1"}}}' ;;
  "pane run")   env -u HARNESS_MAINTAINER bash -c "$4" ;;
esac
EOF
cat > "$hs/claude" <<'EOF'
#!/usr/bin/env bash
echo "${HARNESS_MAINTAINER-unset}" > "$HERDR_STUB_LOG.claude"
EOF
chmod +x "$hs/herdr" "$hs/claude"
mkdir -p "$wt/.claude/agents"
printf -- '---\nname: demo\nmodel: haiku\n---\n' > "$wt/.claude/agents/demo.md"

# herdr_case <name> <caller's HARNESS_MAINTAINER, "" = unset> <in tab env: yes|no> <run script's value, "" = interactive> [start opts]
herdr_case() {
  local name="$1" maint="$2" want_tab="$3" want_run="$4" log="$aux/herdr.log" got_tab=no got_run launched='^pane run '
  shift 4
  [ -n "$want_run" ] || launched='^agent start '
  rm -f "$log" "$log.claude"
  if ! ( cd "$wt" || exit 1
         unset HARNESS_MAINTAINER HERDR_SUB_CLAUDE_ARGS
         [ -n "$maint" ] && export HARNESS_MAINTAINER="$maint"
         HERDR_ENV=1 HERDR_WORKSPACE_ID=w1 HERDR_STUB_LOG="$log" PATH="$hs:$PATH" \
           "$ROOT/scripts/herdr-sub.sh" start demo "hello" "$@" ) >/dev/null 2>&1; then
    bad "herdr-sub: $name (start failed)"; return
  fi
  # Both must have happened, or "absent" below would pass on a run that never started.
  if ! grep -q '^tab create ' "$log" || ! grep -q "$launched" "$log"; then
    bad "herdr-sub: $name (no tab or no launch: $(tr '\n' ';' < "$log"))"; return
  fi
  grep -q '^tab create .*--env HARNESS_MAINTAINER=1' "$log" && got_tab=yes
  got_run="$(cat "$log.claude" 2>/dev/null)"
  if [ "$got_tab" != "$want_tab" ]; then bad "herdr-sub: $name (tab env: want $want_tab, got $got_tab)"
  elif [ "$got_run" != "$want_run" ]; then bad "herdr-sub: $name (run script: want '$want_run', got '$got_run')"
  else ok "herdr-sub: $name"; fi
}
herdr_case "headless: forwarded when set"    1  yes 1
herdr_case "headless: absent when unset"     "" no  unset
herdr_case "headless: only 1 means on"       0  no  unset
herdr_case "interactive: forwarded when set" 1  yes "" --interactive
herdr_case "interactive: absent when unset"  "" no  "" --interactive

# ---------------- 9. /finish order ----------------
# reviewer reads `git diff main...HEAD`, so the commit has to come before it.
finish="$ROOT/.claude/commands/finish.md"
step() { grep -nE "^[0-9]+\. .*$1" "$finish" | head -n1 | cut -d: -f1; }
prev=0; order_ok=1
for s in 'scripts/verify.sh' 'Commit the work' 'to `reviewer`' 'Write `.agent/receipts' 'Commit the receipt'; do
  n="$(step "$s")"
  if [ -z "$n" ] || [ "$n" -le "$prev" ]; then order_ok=0; bad "finish: step out of order: $s"; fi
  prev="${n:-$prev}"
done
[ "$order_ok" = 1 ] && ok "finish: verify, commit, review, receipt, commit receipt"

# ---------------- 10. hygiene (maintainers of this boilerplate only) ----------------
# Tracked files ship to template users, so nothing from a maintainer's machine may leak into them.
# The patterns are split so this file doesn't match itself.
# The public repo slug is the one allowed form of the owner name, exact and case-sensitive, because
# the docs must link to it. It is cut out of the line, not skipped: a bare name beside it still hits.
hygiene_hits() { # hygiene_hits <repo>: prints every banned string in its tracked files
  local names='acade''mos|heph''est' slug='Heph''est/coding-harness-boilerplate' edge='[^[:alnum:]_-]'
  git -C "$1" grep -nIiE "$names" -- . | sed -E "s#($edge)$slug(\$|$edge)#\1\2#g" | grep -iE "$names"
  git -C "$1" grep -nIE '/Use''rs/' -- .
}

# hygiene_case <clean|dirty> <name> <file text>
hy="$aux/hygiene"; mkdir -p "$hy"; : > "$hy/doc.md"
g "$hy" init -q; g "$hy" add -A
hygiene_case() {
  local got=dirty
  printf '%s\n' "$3" > "$hy/doc.md"
  [ -z "$(hygiene_hits "$hy")" ] && got=clean
  if [ "$got" = "$1" ]; then ok "hygiene: $2"; else bad "hygiene: $2 (want $1, got $got)"; fi
}
owner='Heph''est'; slug="$owner/coding-harness-boilerplate"
hygiene_case clean "nothing banned"           "plain text"
hygiene_case clean "slug in a url"            "https://github.com/$slug/commits/main"
hygiene_case clean "slug with .git"           "git clone https://github.com/$slug.git"
hygiene_case clean "slug twice on a line"     "[$slug](https://github.com/$slug)"
hygiene_case dirty "bare owner name"          "by $owner"
hygiene_case dirty "bare name beside slug"    "$slug by $owner"
hygiene_case dirty "slug in lower case"       "github.com/heph""est/coding-harness-boilerplate"
hygiene_case dirty "slug in upper case"       "github.com/HEPH""EST/coding-harness-boilerplate"
hygiene_case dirty "owner's other repo"       "github.com/$owner/other-repo"
hygiene_case dirty "longer repo name"         "github.com/$slug-private"
hygiene_case dirty "longer owner name"        "github.com/not$slug"
hygiene_case dirty "other banned name"        "acade""mos"
hygiene_case dirty "home path"                "/Use""rs/someone/project"
hygiene_case dirty "home path beside slug"    "$slug /Use""rs/someone/project"

if [ "${HARNESS_MAINTAINER:-}" = 1 ]; then
  hits="$(hygiene_hits "$ROOT")"
  if [ -z "$hits" ]; then ok "hygiene: no personal strings in tracked files"
  else bad "hygiene: personal strings in tracked files"; printf '%s\n' "$hits" | sed 's/^/      /'; fi
else
  echo "SKIP  hygiene (HARNESS_MAINTAINER unset)"
fi

# ---------------- 11. topic case files ----------------
# Each topic keeps its cases in its own file. They share this file's fixture and helpers.
for cases in "$ROOT"/tests/harness/cases-*.sh; do
  # shellcheck disable=SC1090
  [ -f "$cases" ] && . "$cases"
done

echo "=== harness self-test: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
