# Cases for scripts/harness-init.sh. Sourced by run.sh: uses its ok/bad helpers and $aux.
# Every target is a fresh mktemp dir under $aux, which run.sh removes on exit.
hi="$ROOT/scripts/harness-init.sh"
hi_new() { mktemp -d "$aux/init.XXXXXX"; }
# hi_tree <dir>: file list + content hash, to compare before/after.
hi_tree() { ( cd "$1" && find . | LC_ALL=C sort | while IFS= read -r f; do [ -f "$f" ] && cksum < "$f" | sed "s|^|$f |" || echo "$f"; done ); }

# no clobber: existing files stay byte for byte, each skip is reported
t="$(hi_new)"
printf 'mine\n' > "$t/CLAUDE.md"; mkdir -p "$t/scripts"; printf 'mine\n' > "$t/scripts/verify.sh"
out="$("$hi" "$t" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && [ "$(cat "$t/CLAUDE.md")" = mine ] && [ "$(cat "$t/scripts/verify.sh")" = mine ] \
   && [[ "$out" == *"skip   CLAUDE.md"* ]] && [[ "$out" == *"skip   scripts/verify.sh"* ]] \
   && [[ "$out" == *"merge"* ]] && [ -f "$t/.claude/hooks/guard-write.sh" ]; then
  ok "harness-init: no clobber"; else bad "harness-init: no clobber (rc=$rc: $out)"; fi

# idempotent: .gitignore gets the missing lines once; a second run changes nothing
t="$(hi_new)"
printf 'node_modules/\ncustom\n' > "$t/.gitignore"
"$hi" "$t" >/dev/null 2>&1
first="$(hi_tree "$t")"; gi="$(cat "$t/.gitignore")"
out="$("$hi" "$t" 2>&1)"; rc=$?
dups="$(grep -v '^#' "$t/.gitignore" | grep -v '^$' | sort | uniq -d)"
if [ "$rc" = 0 ] && [ "$first" = "$(hi_tree "$t")" ] && [ "$gi" = "$(cat "$t/.gitignore")" ] && [ -z "$dups" ] \
   && grep -qxF 'custom' "$t/.gitignore" && grep -qxF '.worktrees/' "$t/.gitignore" && [[ "$out" == *"0 copied"* ]]; then
  ok "harness-init: idempotent"; else bad "harness-init: idempotent (rc=$rc dups=$dups)"; fi

# placeholders: --name/--stack change only the two header lines, and only in a CLAUDE.md we copied
# A project that has filled in either one has nothing left for this row to change.
if grep -qF '<project name>' "$ROOT/CLAUDE.md" && grep -qF '<language, framework, DB>' "$ROOT/CLAUDE.md"; then
  t="$(hi_new)"
  "$hi" --name 'Acme & Co/x' --stack 'Go, chi, PG' "$t" >/dev/null 2>&1
  d="$(diff "$ROOT/CLAUDE.md" "$t/CLAUDE.md" | grep -c '^[<>]')"
  if grep -qxF -- '- **What:** Acme & Co/x: <one sentence on what this repo does>' "$t/CLAUDE.md" \
     && grep -qxF -- '- **Stack:** Go, chi, PG' "$t/CLAUDE.md" && [ "$d" = 4 ]; then
    ok "harness-init: placeholders"; else bad "harness-init: placeholders (changed lines: $d)"; fi
else
  echo "SKIP  harness-init: placeholders (CLAUDE.md here has them filled in)"
fi
t="$(hi_new)"; printf '<project name> keep\n' > "$t/CLAUDE.md"
"$hi" --name X "$t" >/dev/null 2>&1
if [ "$(cat "$t/CLAUDE.md")" = '<project name> keep' ]; then ok "harness-init: placeholders (own CLAUDE.md untouched)"
else bad "harness-init: placeholders (own CLAUDE.md edited)"; fi

# sensors: reported, verify.sh untouched, exit 78 called out when none
t="$(hi_new)"
out="$("$hi" "$t" 2>&1)"
if [[ "$out" == *"none detected"* ]] && [[ "$out" == *"78"* ]] && cmp -s "$ROOT/scripts/verify.sh" "$t/scripts/verify.sh"; then
  ok "harness-init: sensors (none)"; else bad "harness-init: sensors (none): $out"; fi
t="$(hi_new)"; printf '{"scripts":{"test":"x","lint":"y"}}\n' > "$t/package.json"; : > "$t/tsconfig.json"
out="$("$hi" "$t" 2>&1)"
if [[ "$out" == *"typecheck: tsc"* ]] && [[ "$out" == *"lint: npm run lint"* ]] && [[ "$out" == *"test: npm test"* ]] \
   && [[ "$out" != *"none detected"* ]] && cmp -s "$ROOT/scripts/verify.sh" "$t/scripts/verify.sh"; then
  ok "harness-init: sensors (npm)"; else bad "harness-init: sensors (npm): $out"; fi

# dry run: nothing on disk, not even the target dir
t="$aux/init.dry.$$"
out="$("$hi" --dry-run --name N "$t" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && [ ! -e "$t" ] && [[ "$out" == *"would copy"* ]]; then ok "harness-init: dry run (new dir)"
else bad "harness-init: dry run (new dir) rc=$rc"; fi
t="$(hi_new)"; printf 'x\n' > "$t/.gitignore"; before="$(hi_tree "$t")"
"$hi" --dry-run "$t" >/dev/null 2>&1
if [ "$before" = "$(hi_tree "$t")" ]; then ok "harness-init: dry run (existing dir)"; else bad "harness-init: dry run (existing dir) changed files"; fi

# A stand-in boilerplate with task history in it, so the cases below don't depend on this checkout.
fake="$(hi_new)"; fhi="$fake/scripts/harness-init.sh"
mkdir -p "$fake/scripts" "$fake/.claude" "$fake/.agent/contracts" "$fake/.agent/receipts" "$fake/.agent/state"
cp -p "$hi" "$fhi"; echo '# c' > "$fake/CLAUDE.md"; echo 0 > "$fake/.claude/HARNESS_VERSION"
for f in contracts/TEMPLATE.md contracts/old-task.md receipts/TEMPLATE.md receipts/old-task.md state/active-task state/.gitkeep; do
  echo x > "$fake/.agent/$f"; done
echo x > "$fake/README.md"

# no task history: only TEMPLATE.md from contracts/receipts; state has just .gitkeep; modes kept
t="$(hi_new)"
"$fhi" "$t" >/dev/null 2>&1
hist="$(ls "$t/.agent/contracts" "$t/.agent/receipts" | grep -v -e '^TEMPLATE.md$' -e ':$' -e '^$')"
st="$(ls -A "$t/.agent/state")"
if [ -z "$hist" ] && [ -f "$t/.agent/contracts/TEMPLATE.md" ] && [ -f "$t/.agent/receipts/TEMPLATE.md" ] \
   && [ "$st" = .gitkeep ] && [ -x "$t/scripts/harness-init.sh" ] && [ ! -e "$t/README.md" ]; then
  ok "harness-init: no task history"; else bad "harness-init: no task history (hist=$hist state=$st)"; fi
t="$(hi_new)"; "$hi" "$t" >/dev/null 2>&1
if [ -x "$t/scripts/verify.sh" ] && [ -x "$t/.claude/hooks/guard-write.sh" ] && [ ! -e "$t/CHANGELOG.md" ] && [ ! -e "$t/LICENSE" ]; then
  ok "harness-init: no task history (modes, no project docs)"; else bad "harness-init: modes or project docs"; fi

# refuses: inside the boilerplate (existing or new path), bad arguments exit 2, no network tools
"$fhi" "$fake/.claude" >/dev/null 2>&1; r1=$?
"$fhi" "$fake/new-dir/sub" >/dev/null 2>&1; r2=$?
"$fhi" "$fake" >/dev/null 2>&1; r3=$?
"$hi" >/dev/null 2>&1; r4=$?
"$hi" --bogus "$aux" >/dev/null 2>&1; r5=$?
if [ "$r1" = 1 ] && [ "$r2" = 1 ] && [ "$r3" = 1 ] && [ ! -e "$fake/new-dir" ] && [ ! -e "$fake/.claude/.claude" ] && [ "$r4" = 2 ] && [ "$r5" = 2 ] \
   && ! grep -v '^ *#' "$hi" | grep -qE '\b(curl|wget|git clone|ssh)\b'; then
  ok "harness-init: refuses"; else bad "harness-init: refuses (rc $r1 $r2 $r3 $r4 $r5)"; fi

# settings merge: a kept .claude/settings.json means no hooks and no deny rules. Exit stays 0 and the
# file stays as it was, but the warning has to be loud, and it has to be the first next step.
t="$(hi_new)"; mkdir -p "$t/.claude"; printf '{"mine":true}\n' > "$t/.claude/settings.json"
out="$("$hi" "$t" 2>&1)"; rc=$?
nxt="${out#*Next steps}"
if [ "$rc" = 0 ] && [ "$(cat "$t/.claude/settings.json")" = '{"mine":true}' ] \
   && [[ "$out" == *"WARNING: "*"settings.json already exists and was NOT changed"* ]] && [[ "$out" == *"GUARDS ARE OFF"* ]] \
   && [[ "$nxt" == *"0. WARNING"* ]] && [[ "$nxt" == *"merge the hooks and deny rules"* ]]; then
  ok "harness-init: settings merge: kept settings.json is warned about"; else bad "harness-init: settings merge: kept settings.json is warned about (rc=$rc: $out)"; fi
# Not a false alarm: a copy identical to ours (a re-run), or one that already has the hooks and deny rules.
t="$(hi_new)"; "$hi" "$t" >/dev/null 2>&1; out="$("$hi" "$t" 2>&1)"
if [[ "$out" != *WARNING* ]]; then ok "harness-init: settings merge: no warning on a re-run"; else bad "harness-init: settings merge: no warning on a re-run"; fi
t="$(hi_new)"; mkdir -p "$t/.claude"
printf '{"x":1,"hooks":{"PreToolUse":[{"hooks":[{"command":".claude/hooks/guard-bash.sh"}]}]},"permissions":{"deny":["Bash(rm *)"]}}\n' > "$t/.claude/settings.json"
out="$("$hi" "$t" 2>&1)"
if [[ "$out" != *WARNING* ]]; then ok "harness-init: settings merge: no warning once merged"; else bad "harness-init: settings merge: no warning once merged"; fi

# sensors for Python: tests/harness alone is not a test suite, and --dry-run says what a real run says.
pyb="$(hi_new)"; printf '#!/bin/sh\nexit 0\n' > "$pyb/pytest"; chmod +x "$pyb/pytest"
hi_sensors() { # hi_sensors <target> [--dry-run] : the sensors block only
  local o; o="$(PATH="$pyb:$PATH" "$hi" ${2:+"$2"} "$1" 2>&1)"; o="${o#*sensors}"; printf '%s' "${o%%harness-init:*}"; }
t="$(hi_new)"; : > "$t/pyproject.toml"
real="$(hi_sensors "$t")"
t2="$(hi_new)"; : > "$t2/pyproject.toml"
dry="$(hi_sensors "$t2" --dry-run)"
if [[ "$real" != *pytest* ]] && [[ "$dry" != *pytest* ]]; then ok "harness-init: sensors (python, no tests): no pytest from tests/harness"
else bad "harness-init: sensors (python, no tests): no pytest from tests/harness (real: $real dry: $dry)"; fi
[ "$real" = "$dry" ] && ok "harness-init: sensors (python, no tests): dry run agrees" || bad "harness-init: sensors (python, no tests): dry run agrees"
for tf in tests/test_a.py tests/unit/b_test.py; do
  t="$(hi_new)"; : > "$t/pyproject.toml"; mkdir -p "$t/$(dirname "$tf")"; : > "$t/$tf"
  real="$(hi_sensors "$t")"; dry="$(hi_sensors "$t" --dry-run)"
  if [[ "$real" == *"test: pytest"* ]] && [[ "$dry" == *"test: pytest"* ]]; then ok "harness-init: sensors (python, $tf): pytest, dry run agrees"
  else bad "harness-init: sensors (python, $tf): pytest, dry run agrees (real: $real dry: $dry)"; fi
done
