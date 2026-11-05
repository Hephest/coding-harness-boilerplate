# Sourced by run.sh: the last small guard gaps (contract v02-guard-small). Needs gb and gb_table
# from cases-guard-bash.sh, which sorts first. Rows are data and never run.

# --- Criterion 1: {a..b} is a word only the shell can expand, same as {a,b}: pass and log ---
: > "$gb_log"
gb_table 0 "final: sequence braces" <<'ROWS'
wt	echo x > .claude/hooks/{a..b}.sh
wt	echo x > scripts/verify{1..3}.sh
wt	rm -f .claude/hooks/{a..c}
wt	echo x > .claude/hooks/{a,b}.sh
ROWS
for needle in 'unresolved target: .claude/hooks/{a..b}.sh' 'unresolved target: scripts/verify{1..3}.sh' \
              'unresolved target: .claude/hooks/{a..c}' 'unresolved target: .claude/hooks/{a,b}.sh'; do
  if grep -qF "$needle" "$gb_log"; then ok "guard-bash: final: sequence braces: logged: $needle"
  else bad "guard-bash: final: sequence braces: logged: $needle"; fi
done
# Dots after the closing brace are a plain path, so it is still checked.
gb 2 "final: sequence braces: {a}/.. is no sequence" "$wt" 'echo x > {a}/../.claude/hooks/x.sh' "harness infrastructure"

# --- Criterion 2: drivers, tools and pagers run a program ---
gb_table 2 "final: git config" <<'ROWS'
wt	git config diff.x.command /tmp/x
wt	git config diff.x.textconv /tmp/x
wt	git config DIFF.x.TEXTCONV /tmp/x
wt	git config diff.a.b.command /tmp/x
wt	git config --local diff.x.command /tmp/x
wt	git config set diff.x.command /tmp/x
wt	git config merge.x.driver /tmp/x
wt	git config --add merge.x.driver /tmp/x
wt	git config difftool.x.cmd /tmp/x
wt	git config mergetool.x.cmd /tmp/x
wt	git config pager.log /tmp/x
wt	git config Pager.Log /tmp/x
wt	git config --remove-section difftool
wt	git config --remove-section mergetool
wt	git config --remove-section pager
wt	git -c diff.x.command=/tmp/x diff
wt	git -c diff.x.textconv=/tmp/x log -p
wt	git -c merge.x.driver=/tmp/x merge y
wt	git -c difftool.x.cmd=/tmp/x difftool
wt	git -c mergetool.x.cmd=/tmp/x mergetool
wt	git -c pager.log=/tmp/x log
wt	git --config-env=pager.log=X log
ROWS
gb 2 "final: git config: says why" "$wt" 'git config pager.log /tmp/x' "can run code"
gb_table 0 "final: git config: harmless" <<'ROWS'
wt	git config diff.renames true
wt	git config merge.ff false
wt	git config merge.conflictStyle diff3
wt	git config diff.tool x
wt	git -c diff.renames=false diff
wt	git config diff.x.command
wt	git config pager.log
wt	git config --get diff.x.textconv
wt	git config get merge.x.driver
wt	git config --list
ROWS

# --- Criterion 3: the stopping rule for reviews ---
grep -q 'documentation item, not a blocker' "$ROOT/.claude/agents/reviewer.md" \
  && ok "final: reviewer: hostile evasion is a documentation item" \
  || bad "final: reviewer: hostile evasion is a documentation item"
grep -q 'affect the verdict' "$ROOT/.claude/agents/reviewer.md" \
  && ok "final: reviewer: it doesn't affect the verdict" \
  || bad "final: reviewer: it doesn't affect the verdict"
