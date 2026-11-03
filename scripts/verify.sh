#!/usr/bin/env bash
# The ONLY definition of "done". Exit 0 = all sensors passed.
#   scripts/verify.sh            full suite: typecheck, lint, tests, scoped sensors
#   scripts/verify.sh --fast F   quick check of one file (used by the PostToolUse hook)
#
# Exit codes: 0 all sensors passed · 1 a sensor failed · 78 no sensors configured (setup missing)
#
# Edit the CONFIG block for your stack. Empty command = auto-detect.
# This script never modifies or restores the working tree.
set -uo pipefail
cd "$(dirname "$0")/.." && cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# ---------------- CONFIG ----------------
TYPECHECK_CMD=""     # e.g. "npx tsc --noEmit"   | "pyright"
LINT_CMD=""          # e.g. "npx eslint ."       | "ruff check ."
TEST_CMD=""          # e.g. "npm test --silent"  | "pytest -q --timeout=60"
# Path-scoped sensors: "path-prefix|command". Run only when files under the prefix changed.
SCOPED_SENSORS=(
  # "src/auth/|pytest tests/auth -q --timeout=10"
)
FORMAT_ON_EDIT=1     # 1 = format each edited file (ruff format / prettier / gofmt / rustfmt) before checks
# ----------------------------------------

has() { command -v "$1" >/dev/null 2>&1; }
detect() {
  if [ -f package.json ]; then
    [ -z "$TYPECHECK_CMD" ] && [ -f tsconfig.json ] && TYPECHECK_CMD="npx --no-install tsc --noEmit"
    [ -z "$LINT_CMD" ] && grep -q '"lint"' package.json && LINT_CMD="npm run lint --silent"
    [ -z "$TEST_CMD" ] && grep -q '"test"' package.json && TEST_CMD="npm test --silent"
  fi
  if [ -f pyproject.toml ] || [ -f setup.cfg ] || [ -f requirements.txt ]; then
    [ -z "$TYPECHECK_CMD" ] && has pyright && TYPECHECK_CMD="pyright"
    [ -z "$LINT_CMD" ] && has ruff && LINT_CMD="ruff check ."
    [ -z "$TEST_CMD" ] && has pytest && [ -d tests ] && TEST_CMD="pytest -q"
  fi
}

failed=0
run() { # run <name> <cmd>
  local name="$1" cmd="$2" start out code
  start=$(date +%s)
  out="$(bash -c "$cmd" 2>&1)"; code=$?
  if [ $code -eq 0 ]; then
    echo "PASS  $name ($(( $(date +%s) - start ))s)"
  else
    echo "FAIL  $name (exit $code): $cmd"
    printf '%s\n' "$out" | tail -n 40 | sed 's/^/      /'
    failed=1
  fi
}

# ---- fast mode: one file ----
if [ "${1:-}" = "--fast" ]; then
  f="${2:?usage: verify.sh --fast <file>}"
  if [ "$FORMAT_ON_EDIT" = 1 ]; then   # format quietly; a formatter failure is reported by the checks below
    case "$f" in
      *.py)                     has ruff && ruff format -q "$f" >/dev/null 2>&1 ;;
      *.ts|*.tsx|*.js|*.jsx|*.css|*.scss|*.md|*.json|*.yaml|*.yml)
                                [ -x node_modules/.bin/prettier ] && node_modules/.bin/prettier --log-level silent --write "$f" >/dev/null 2>&1 ;;
      *.go)                     has gofmt && gofmt -w "$f" >/dev/null 2>&1 ;;
      *.rs)                     has rustfmt && rustfmt -q "$f" >/dev/null 2>&1 ;;
    esac
  fi
  case "$f" in
    *.py)          has ruff && run "ruff $f" "ruff check '$f'"
                   run "syntax $f" "python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])' '$f'" ;;
    *.ts|*.tsx|*.js|*.jsx)
                   [ -x node_modules/.bin/eslint ] && run "eslint $f" "node_modules/.bin/eslint '$f'" ;;
    *.sh)          run "bash -n $f" "bash -n '$f'" ;;
    *.json)        if has jq; then run "json $f" "jq empty '$f'"
                   elif has python3; then run "json $f" "python3 -m json.tool '$f' >/dev/null"
                   else echo "WARN  json $f: skipped, no jq or python3"; fi ;;
  esac
  exit $failed
fi

# ---- full mode ----
detect
if [ -z "$TYPECHECK_CMD$LINT_CMD$TEST_CMD" ] && [ ${#SCOPED_SENSORS[@]} -eq 0 ]; then
  if [ "${HARNESS_MAINTAINER:-}" = 1 ] && [ -x tests/harness/run.sh ]; then
    # Developing the boilerplate itself: the harness self-test is the sensor suite.
    TEST_CMD="tests/harness/run.sh"
  else
    echo "FAIL  no sensors configured, so nothing can be verified."
    echo "      A human must set TYPECHECK_CMD / LINT_CMD / TEST_CMD in the CONFIG block of"
    echo "      scripts/verify.sh. Harness files are human-owned: Claude can only propose the change."
    exit 78   # EX_CONFIG: setup missing, not a code failure
  fi
fi

echo "=== SENSOR SUITE ==="
[ -n "$TYPECHECK_CMD" ] && run "typecheck" "$TYPECHECK_CMD"
[ -n "$LINT_CMD" ]      && run "lint" "$LINT_CMD"
[ -n "$TEST_CMD" ]      && run "tests" "$TEST_CMD"

base="$(git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null || echo HEAD)"
changed="$( { git diff --name-only "$base"; git status --porcelain | cut -c4-; } 2>/dev/null | sort -u)"
for entry in ${SCOPED_SENSORS[@]+"${SCOPED_SENSORS[@]}"}; do
  prefix="${entry%%|*}"; cmd="${entry#*|}"
  grep -q "^$prefix" <<< "$changed" && run "scoped:$prefix" "$cmd"
done

[ $failed -eq 0 ] && echo "=== ALL SENSORS PASSED ===" || echo "=== SENSORS FAILED ==="
exit $failed
