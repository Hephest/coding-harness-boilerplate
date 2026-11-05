#!/usr/bin/env bash
# Copy the harness into a new or existing project. Automates README Quickstart option C.
#   scripts/harness-init.sh [--name NAME] [--stack STACK] [--dry-run] <target-dir>
#
# Never overwrites: a file that already exists in the target is skipped and reported.
# Never edits verify.sh, runs git, or touches the network. Everything that needs a human
# (protected-paths, sensors, the first commit) is printed as a next step.
set -uo pipefail

usage() {
  echo "usage: ${0##*/} [--name NAME] [--stack STACK] [--dry-run] <target-dir>" >&2
  exit 2
}

name=""; stack=""; dry=0; target=""
while [ $# -gt 0 ]; do
  case "$1" in
    --name)    [ $# -ge 2 ] || usage; name="$2"; shift 2 ;;
    --stack)   [ $# -ge 2 ] || usage; stack="$2"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    -h|--help) usage ;;
    -*)        echo "harness-init: unknown option: $1" >&2; usage ;;
    *)         [ -z "$target" ] || usage; target="$1"; shift ;;
  esac
done
[ -n "$target" ] || usage

SRC="$(cd "$(dirname "$0")/.." && pwd -P)"

# Absolute, symlink-free path even when the target doesn't exist yet (walk up to a real ancestor).
resolve() {
  local p="$1" rest=""
  while [ ! -d "$p" ]; do
    rest="/$(basename "$p")$rest"
    p="$(dirname "$p")"
  done
  printf '%s%s\n' "$(cd "$p" && pwd -P)" "$rest"
}
dest="$(resolve "$target")"

# Copying the harness into itself would nest copies or overwrite the maintainer's own files.
case "$dest/" in
  "$SRC"/*) echo "harness-init: refusing, target is inside the boilerplate ($SRC)" >&2; exit 1 ;;
esac

[ -e "$dest" ] && [ ! -d "$dest" ] && { echo "harness-init: target is not a directory: $dest" >&2; exit 1; }

copied=0; skipped=0; settings_skipped=0
say() { if [ "$dry" = 1 ]; then echo "would $1"; else echo "$1"; fi; }

# Task history and run state belong to the boilerplate's maintainers, not to a new project.
want() {
  case "$1" in
    .agent/contracts/*|.agent/receipts/*) [ "${1##*/}" = TEMPLATE.md ] ;;
    .agent/state/*)                       [ "${1##*/}" = .gitkeep ] ;;
    .claude/settings.local.json|*/.DS_Store|.DS_Store) return 1 ;;
    *) return 0 ;;
  esac
}

copy_one() { # copy_one <relative path>
  local rel="$1"
  if [ -e "$dest/$rel" ] || [ -L "$dest/$rel" ]; then
    echo "skip   $rel (already exists)"; skipped=$((skipped + 1))
    # The hooks and deny rules live in this one file, so a kept copy that lacks them means no guards.
    if [ "$rel" = .claude/settings.json ] && ! cmp -s "$SRC/$rel" "$dest/$rel" \
       && ! { grep -q 'guard-bash.sh' "$dest/$rel" 2>/dev/null && grep -q '"deny"' "$dest/$rel" 2>/dev/null; }; then
      settings_skipped=1
    fi
    return
  fi
  if [ "$dry" != 1 ]; then
    mkdir -p "$dest/$(dirname "$rel")" && cp -p "$SRC/$rel" "$dest/$rel" || { echo "harness-init: copy failed: $rel" >&2; exit 1; }
  fi
  say "copy  $rel"; copied=$((copied + 1))
}

claude_md_copied=0
[ -e "$dest/CLAUDE.md" ] || [ -L "$dest/CLAUDE.md" ] || claude_md_copied=1

echo "harness-init: $SRC -> $dest"
[ "$dry" = 1 ] && echo "harness-init: dry run, nothing will be written"

files="$( cd "$SRC" && { [ -f CLAUDE.md ] && echo CLAUDE.md
                         for d in .claude .agent scripts tests docs; do [ -d "$d" ] && find "$d" -type f; done; } | LC_ALL=C sort )"
while IFS= read -r rel; do
  [ -n "$rel" ] && want "$rel" && copy_one "$rel"
done <<EOF_FILES
$files
EOF_FILES

# Hooks and scripts must stay executable (cp -p keeps the mode; this covers a download that lost it).
if [ "$dry" != 1 ]; then
  for f in .claude/hooks/*.sh scripts/*.sh tests/harness/*.sh; do
    [ -f "$dest/$f" ] && [ -f "$SRC/$f" ] && [ -x "$SRC/$f" ] && chmod +x "$dest/$f"
  done
  mkdir -p "$dest/.agent/state"
  [ -e "$dest/.agent/state/.gitkeep" ] || : > "$dest/.agent/state/.gitkeep"
fi

# .gitignore: append only the lines the target lacks; never rewrite what is there.
if [ -f "$SRC/.gitignore" ]; then
  missing=""
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    if [ ! -f "$dest/.gitignore" ] || ! grep -qxF -- "$line" "$dest/.gitignore"; then
      missing="$missing$line
"
    fi
  done < "$SRC/.gitignore"
  if [ -n "$missing" ]; then
    n="$(printf '%s' "$missing" | grep -c '')"
    if [ "$dry" != 1 ]; then
      # A last line without a newline would glue our header onto it.
      if [ -s "$dest/.gitignore" ] && [ -n "$(tail -c 1 "$dest/.gitignore")" ]; then echo >> "$dest/.gitignore"; fi
      { [ -s "$dest/.gitignore" ] && echo; echo "# coding harness"; printf '%s' "$missing"; } >> "$dest/.gitignore"
    fi
    say "append $n line(s) to .gitignore"
  else
    echo "skip   .gitignore (nothing missing)"
  fi
fi

# CLAUDE.md placeholders: only in a file this run copied, and only the two header lines.
fill() { # fill <file> <placeholder> <value>: replace the first match on each line, no escaping needed
  local f="$1" ph="$2" val="$3" line out="" changed=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *"$ph"*) line="${line%%"$ph"*}$val${line#*"$ph"}"; changed=1 ;;
    esac
    out="$out$line
"
  done < "$f"
  [ "$changed" = 1 ] && printf '%s' "$out" > "$f"
}
if [ "$claude_md_copied" = 1 ]; then
  if [ "$dry" != 1 ]; then
    [ -n "$name" ]  && fill "$dest/CLAUDE.md" "<project name>" "$name"
    [ -n "$stack" ] && fill "$dest/CLAUDE.md" "<language, framework, DB>" "$stack"
  fi
  [ -n "$name" ]  && say "fill  CLAUDE.md project name: $name"
  [ -n "$stack" ] && say "fill  CLAUDE.md stack: $stack"
else
  echo "note   CLAUDE.md already exists and was kept; merge $SRC/CLAUDE.md into it by hand"
fi

# Sensors: the same checks verify.sh auto-detects, read from the target. verify.sh is not edited.
has() { command -v "$1" >/dev/null 2>&1; }
# Real Python tests only. tests/harness is ours and arrives with the copy, so a dry run and a real
# run must not differ over it, and a project with no tests of its own must not be told pytest runs.
# Same test as verify.sh.
has_py_tests() { # has_py_tests <tests dir>
  [ -d "$1" ] && find "$1" -path "$1/harness" -prune -o -type f \( -name 'test_*.py' -o -name '*_test.py' \) -print 2>/dev/null | grep -q .
}
sensors=""
add() { sensors="$sensors  - $1
"; }
if [ -f "$dest/package.json" ]; then
  [ -f "$dest/tsconfig.json" ] && add "typecheck: tsc (tsconfig.json)"
  grep -q '"lint"' "$dest/package.json" && add "lint: npm run lint"
  grep -q '"test"' "$dest/package.json" && add "test: npm test"
fi
if [ -f "$dest/pyproject.toml" ] || [ -f "$dest/setup.cfg" ] || [ -f "$dest/requirements.txt" ]; then
  has pyright && add "typecheck: pyright"
  has ruff && add "lint: ruff"
  has pytest && has_py_tests "$dest/tests" && add "test: pytest"
fi
echo
if [ -n "$sensors" ]; then
  echo "sensors verify.sh should auto-detect:"; printf '%s' "$sensors"
else
  echo "sensors: none detected. scripts/verify.sh exits 78 (no sensors configured) until you set"
  echo "         TYPECHECK_CMD / LINT_CMD / TEST_CMD in its CONFIG block. That exit is expected."
fi

echo
if [ "$settings_skipped" = 1 ]; then
  echo "WARNING: $dest/.claude/settings.json already exists and was NOT changed."
  echo "         The harness hooks and deny rules live there, so THE GUARDS ARE OFF in this project"
  echo "         until you merge them in from $SRC/.claude/settings.json."
  echo
fi
echo "harness-init: $copied copied, $skipped skipped"
echo
echo "Next steps (need a human):"
if [ "$settings_skipped" = 1 ]; then
  echo "  0. WARNING, do this first: merge the hooks and deny rules from the boilerplate's"
  echo "     .claude/settings.json into $dest/.claude/settings.json. Until then nothing is guarded."
fi
cat <<'NEXT'
  1. CLAUDE.md: fill the remaining <placeholders> (run command) and adjust the repo map.
  2. scripts/verify.sh: set the sensor commands in the CONFIG block (harness files are human-owned).
  3. .claude/protected-paths: list your danger zones.
  4. README, CHANGELOG, LICENSE, SECURITY: none were copied; write your project's own.
  5. git init -b main   (skip if the repo exists), then
     git add -A && git commit -m "chore: add coding harness"
  6. claude, then: /task <task-id> <goal>
NEXT
