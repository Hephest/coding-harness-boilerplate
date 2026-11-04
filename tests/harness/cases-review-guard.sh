# Sourced by run.sh: bypasses confirmed by cold review (contract v02-review-guard).
# Needs ca_contract, ca_approve and ca_write from cases-contract-approval.sh, gb, gb_expand and the
# par_* helpers from cases-guard-bash.sh, and jp from cases-guard-policy.sh, which all sort first.
# Rows are data and never run. Leaves the fixture as it found it.

# rg_rows <expected-exit> <label> <text stderr must contain> : one command per line on stdin, all
# from $wt. The text matters: there a write can also block for being outside the contract.
rg_rows() {
  local want="$1" label="$2" needle="$3" cmd
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    par_begin
    gb "$want" "review: $label: $cmd" "$wt" "$(gb_expand "$cmd")" "$needle" > "$PF" &
    par_end $!
  done
  par_flush
}

# rg_write <expected-exit> <name> <path> [text] and rg_shell <expected-exit> <name> <cwd> <command> [text]
rg_write() { ca_write "$1" "review: $2" "$3" "${4:-}"; }
rg_shell() { gb "$1" "review: $2" "$3" "$4" "${5:-}"; }

# --- Criterion 1: on task/<id> with a contract or a record, that id sets approval and scope ---
g "$fx" worktree add -q -b task/rg "$fx/.worktrees/rg" HEAD
rw="$fx/.worktrees/rg"
rstate="$rw/.agent/state/active-task"
mkdir -p "$rw/src/billing"
ca_contract "$rw" rg
ca_approve "$rw" rg
# An unapproved contract with a wider scope, for active-task to point at.
printf '# Contract: wide\n## Target files\n- src/*\n- `src/billing/*`\n' > "$rw/.agent/contracts/wide.md"

rg_write 2 "one task id: no active-task, write outside the contract" "$rw/src/other.py" "outside the contract for 'rg'"
rg_shell 2 "one task id: no active-task, shell write outside" "$rw" 'echo x > src/other.py' "outside the contract for 'rg'"
rg_write 0 "one task id: no active-task, target allowed" "$rw/src/app.py"
: > "$rstate"
rg_write 2 "one task id: blank active-task, write outside the contract" "$rw/src/other.py" "outside the contract for 'rg'"
rg_shell 2 "one task id: blank active-task, shell write outside" "$rw" 'echo x > src/other.py' "outside the contract for 'rg'"
rg_write 2 "one task id: blank active-task, danger zone" "$rw/src/billing/pay.py" "danger zone"
rg_write 0 "one task id: blank active-task, target allowed" "$rw/src/extra.py"
printf ' \n' > "$rstate"
rg_write 2 "one task id: whitespace active-task, write outside" "$rw/src/other.py" "outside the contract for 'rg'"
echo wide > "$rstate"
rg_write 2 "one task id: unapproved contract in active-task gives no scope" "$rw/src/other.py" "outside the contract for 'rg'"
rg_shell 2 "one task id: unapproved contract in active-task, shell" "$rw" 'echo x > src/other.py' "outside the contract for 'rg'"
rg_write 2 "one task id: unapproved contract in active-task, danger zone" "$rw/src/billing/pay.py" "contract for 'rg'"
rg_write 0 "one task id: unapproved contract in active-task, target allowed" "$rw/src/app.py"
echo ghost > "$rstate"
rg_write 0 "one task id: active-task with no contract changes nothing" "$rw/src/app.py"
rg_write 2 "one task id: active-task with no contract, outside" "$rw/src/other.py" "outside the contract for 'rg'"
# The other way round: an approved contract in active-task can't stand in for the branch's own.
ca_contract "$rw" okay
ca_approve "$rw" okay
echo okay > "$rstate"
printf '\n' >> "$rw/.agent/contracts/rg.md"
rg_write 2 "one task id: edited contract, approved one in active-task" "$rw/src/app.py" "changed since"
rg_write 0 "one task id: a blocked agent can still fix its contract" "$rw/.agent/contracts/rg.md"
ca_contract "$rw" rg
rg_write 0 "one task id: contract restored as approved" "$rw/src/app.py"
cp "$rw/.agent/contracts/rg.md" "$aux/rg.md.keep"
rm -f "$rw/.agent/contracts/rg.md"
rg_write 2 "one task id: deleted contract stays blocked" "$rw/src/app.py" "was approved"
rg_write 0 "one task id: deleted contract, .agent stays open" "$rw/.agent/contracts/rg.md"
: > "$rstate"
rg_write 2 "one task id: deleted contract, blank active-task" "$rw/src/app.py" "was approved"
cp "$aux/rg.md.keep" "$rw/.agent/contracts/rg.md"
rm -f "$rstate"

# Git failing keeps the block it has today: the id is the branch's, and it can't be checked.
stubgit="$(tool_dir rg-nocommon cat dirname "$jp")"
cat > "$stubgit/git" <<EOF
#!/bin/sh
case "\$*" in *--git-common-dir*) exit 1 ;; esac
exec "$(command -v git)" "\$@"
EOF
chmod +x "$stubgit/git"
guard_raw 2 "review: one task id: no common dir fails closed" "$stubgit" "$(input "$rw/src/app.py")" "common dir"

# --- Criterion 2, replaced by v02-task-branch: a task branch with no contract of its own blocks,
# whatever active-task names. Same rows, new expectations. ---
g "$fx" worktree add -q -b task/rgfree "$fx/.worktrees/rgfree" HEAD
rf="$fx/.worktrees/rgfree"
mkdir -p "$rf/.agent/state" "$rf/.agent/contracts"
printf '# Contract: wide\n## Target files\n- src/*\n' > "$rf/.agent/contracts/wide.md"
rg_write 2 "other branch: task branch, nothing to enforce" "$rf/src/other.py" "contracts/rgfree.md doesn't exist"
echo wide > "$rf/.agent/state/active-task"
rg_write 2 "other branch: task branch without a contract, unapproved active-task" "$rf/src/other.py" "contracts/rgfree.md doesn't exist"
rg_shell 2 "other branch: same, shell" "$rf" 'echo x > src/other.py' "contracts/rgfree.md doesn't exist"
rg_write 0 "other branch: same, .agent stays open" "$rf/.agent/contracts/wide.md"
ca_contract "$rf" narrow
ca_approve "$rf" narrow
echo narrow > "$rf/.agent/state/active-task"
rg_write 2 "other branch: task branch, approved active-task, target" "$rf/src/app.py" "contracts/rgfree.md doesn't exist"
rg_write 2 "other branch: task branch, approved active-task, outside" "$rf/src/other.py" "contracts/rgfree.md doesn't exist"
echo ghost > "$rf/.agent/state/active-task"
rg_write 2 "other branch: task branch, active-task has no contract" "$rf/src/app.py" "contracts/rgfree.md doesn't exist"

g "$fx" worktree add -q -b feature/rg "$fx/.worktrees/rgfeat" HEAD
rc="$fx/.worktrees/rgfeat"
mkdir -p "$rc/.agent/state"
ca_contract "$rc" rgfeat
rg_write 0 "other branch: no active task" "$rc/src/other.py"
echo rgfeat > "$rc/.agent/state/active-task"
rg_write 2 "other branch: unapproved active-task" "$rc/src/app.py" "isn't approved"
ca_approve "$rc" rgfeat
rg_write 0 "other branch: approved active-task, target" "$rc/src/app.py"
rg_write 2 "other branch: approved active-task, outside" "$rc/src/other.py" "outside the contract for 'rgfeat'"
rm -f "$rc/.agent/contracts/rgfeat.md"
rg_write 2 "other branch: deleted contract stays blocked" "$rc/src/app.py" "was approved"

g "$fx" worktree remove --force "$rw"
g "$fx" worktree remove --force "$rf"
g "$fx" worktree remove --force "$rc"
g "$fx" branch -qD task/rg task/rgfree feature/rg
rm -f "$store/rg.sha256" "$store/okay.sha256" "$store/narrow.sha256" "$store/rgfeat.sha256"

# --- Criterion 3: $'...' and $"..." are literal text once decoded ---
rg_rows 2 "ansi quoting" "protected path" <<'ROWS'
cat $'.env'
cat $'.e\x6ev'
cat $'.e\x6Ev'
cat $'.e\156v'
cat $'.en'v
cat .e$'nv'
cat $'.env\0junk'
cat $'.en\x00junk'v
cat $'.env\400junk'
cat $".env"
cat .e$"nv"
head -n 1 $'src/.env'
echo x > $'.env'
echo x > $'.e\x6ev'
echo x >> $".env"
cp src/app.py $'.env'
tee $".env"
cat < $'.env'
cat < $".env"
cat < $'.e\156v'
echo "$" > .env
ROWS
rg_rows 2 "ansi quoting: command words" "denied" <<'ROWS'
$'git' push
git $'push'
$"git" push
g$'i't $'pu\x73h'
cat <<$'E'%NL%x%NL%E%NL%git push
ROWS

# Each escape on its own: the link only leads to .env when the directory name decoded exactly.
esc="$aux/esc"; mkdir -p "$esc"
for d in $'a\nb' $'a\tb' 'a\b' "a'b" 'a"b' aAb $'a\ab' $'a\033b' $'a\fb' $'a\rb' $'a\vb' $'a\bb' 'a\qb' $'a\004zb' 'a\xZZb'; do
  mkdir -p "$esc/$d"; ln -s "$wt/.env" "$esc/$d/link"
done
rg_rows 2 "ansi quoting: escapes" "protected path" <<'ROWS'
cat $'%AUX%/esc/a\nb/link'
cat $'%AUX%/esc/a\tb/link'
cat $'%AUX%/esc/a\\b/link'
cat $'%AUX%/esc/a\'b/link'
cat $'%AUX%/esc/a\"b/link'
cat $'%AUX%/esc/a"b/link'
cat $'%AUX%/esc/a\x41b/link'
cat $'%AUX%/esc/a\101b/link'
cat $'%AUX%/esc/a\ab/link'
cat $'%AUX%/esc/a\eb/link'
cat $'%AUX%/esc/a\Eb/link'
cat $'%AUX%/esc/a\fb/link'
cat $'%AUX%/esc/a\rb/link'
cat $'%AUX%/esc/a\vb/link'
cat $'%AUX%/esc/a\bb/link'
cat $'%AUX%/esc/a\qb/link'
cat $'%AUX%/esc/a\x4zb/link'
cat $'%AUX%/esc/a\4zb/link'
cat $'%AUX%/esc/a\33b/link'
cat $'%AUX%/esc/a\xZZb/link'
ROWS

rg_rows 0 "ansi quoting: still fine" "" <<'ROWS'
cat $'src/app.py'
echo x > $'src/app.py'
echo $'a\nb'
echo "$'.env'"
cat "$'.env'"
echo "cost: $"
ROWS

# What still can't be resolved passes and is logged, as before.
: > "$gb_log"
rg_shell 0 "ansi quoting: \\u passes" "$wt" "cat \$'\\u002eenv'"
rg_shell 0 "ansi quoting: \\c passes" "$wt" "cat \$'\\cA'"
rg_shell 0 "ansi quoting: unterminated passes" "$wt" "cat \$'.env"
if [ "$(grep -c 'unresolved target' "$gb_log")" = 2 ]; then ok "guard-bash: review: ansi quoting: unresolved words logged"
else bad "guard-bash: review: ansi quoting: unresolved words logged"; fi
grep -q 'unlexable' "$gb_log" && ok "guard-bash: review: ansi quoting: unterminated logged" \
  || bad "guard-bash: review: ansi quoting: unterminated logged"

# --- Criterion 4: a glob that could name the script, and the script read from stdin ---
rg_rows 2 "self-approval" "only the user" <<'ROWS'
scripts/contract-approv?.sh demo
scripts/contract-*.sh demo
scripts/c* demo
scripts/*.sh demo
./scripts/contract-approve.s[h] demo
./scripts/[a-d]ontract-approve.sh demo
scripts/contract-approve.{sh,x} demo
scripts/{contract-approve,x}.sh demo
scripts/contract-approv{d..f}.sh demo
s*/contract-approv?.sh demo
bash scripts/contract-approv?.sh demo
sh scripts/c* demo
source scripts/contract-*
. scripts/c*
env scripts/contract-a* demo
bash -s demo < scripts/contract-approve.sh
bash -s -- demo < scripts/contract-approve.sh
bash -xs demo < scripts/contract-approve.sh
sh -s demo < ./scripts/contract-approve.sh
bash < scripts/contract-approve.sh
bash 0< scripts/contract-approve.sh
bash -s demo < scripts/contract-approv?.sh
bash /dev/stdin demo < scripts/contract-approve.sh
env bash -s demo < scripts/contract-approve.sh
exec bash -s demo < scripts/contract-approve.sh
bash -c 'bash -s demo < scripts/contract-approve.sh'
cat scripts/contract-approve.sh | bash -s demo
cat scripts/contract-approv?.sh | sh
ROWS
rg_rows 0 "self-approval: other scripts" "" <<'ROWS'
scripts/v*
scripts/verify.s?
scripts/[v]erify.sh
scripts/{x,y}.py
bash scripts/x?.sh
bash -s x < scripts/other.sh
bash scripts/other.sh < scripts/input.txt
cat scripts/contract-approve.sh
cat < scripts/contract-approve.sh
cat scripts/contract-approve.sh | head -n 3
grep x scripts/contract-*
ls scripts/c*
bash -c 'cat' < scripts/contract-approve.sh
bash scripts/other.sh < scripts/contract-approve.sh
cat scripts/contract-approve.sh && bash scripts/other.sh
case $x in a) echo 1 ;; *) echo 2 ;; esac
case $f in *.sh) echo 1 ;; c*) echo 2 ;; esac
case $f in%NL%  *.sh) echo 1 ;;%NL%  *) echo 2 ;;%NL%esac
ROWS

# Past the path limit no word is a name, the same as for a target. It passes and is logged.
: > "$gb_log"
long="$(printf 'x%.0s' $(seq 1 5000))"
rg_shell 0 "self-approval: a word past the limit" "$wt" "scripts/$long*"
grep -q 'word too long' "$gb_log" && ok "guard-bash: review: self-approval: long word logged" \
  || bad "guard-bash: review: self-approval: long word logged"

# --- Criterion 5: --target-directory takes the next word ---
rg_rows 2 "target directory" "harness infrastructure" <<'ROWS'
cp --target-directory .claude/hooks src/app.py
cp --target-directory .claude src/app.py
ln --target-directory .claude/hooks src/app.py
install --target-directory .claude/hooks src/app.py
mv --target-directory .claude/hooks src/app.py
cp --target .claude/hooks src/app.py
cp --t .claude/hooks src/app.py
cp --target=.claude/hooks src/app.py
cp --t=.claude/hooks src/app.py
ROWS
rg_rows 2 "target directory: secrets" "protected path" <<'ROWS'
cp --target-directory secrets src/app.py
cp --target-directory src .env
ROWS
rg_rows 0 "target directory: inside the contract" "" <<'ROWS'
cp --target-directory src x/app.py
ln --target-directory src x/app.py
mv --target-directory src src/app.py
cp --no-target-directory src/app.py src/app.py
ROWS

# --- Criterion 6: the repo the hook started in counts after a cd out of it ---
up="$(dirname "$fx")"
mkdir -p "$aux/plain/dir"
rg_shell 2 "cd out: mv the parent of the repo" "$wt" "cd $aux && mv $up x" "whole repository"
rg_shell 2 "cd out: rm the parent of the repo" "$wt" "cd $aux && rm -rf $up" "whole repository"
rg_shell 2 "cd out: from the main checkout" "$fx" "cd $aux && mv $up x" "whole repository"
rg_shell 2 "cd out: from a subdirectory" "$wt/src" "cd $aux && mv $up x" "whole repository"
rg_shell 2 "cd out: no cd at all, as before" "$wt" "mv $up x" "whole repository"
rg_shell 0 "cd out: an unrelated directory" "$wt" "cd $aux && mv $aux/plain/dir $aux/plain/moved"

# --- Criterion 7: after a cd we can't follow, relative targets count from the last known place ---
rg_rows 2 "cd unresolved" "protected path" <<'ROWS'
cd $PWD && echo x > .env
cd $PWD && cat .env
cd "$X" && echo x > .env
cd "$X" && cat .env
cd $(pick) && echo x > .env
cd `pick` && cat .env
cd - && cat .env
cd - && echo x > .env
cd src/* && echo x > .env
pushd $X && echo x > .env
popd && cat .env
cd $X && cd src && cat .env
cd $X; git rm .env
cd $X && git show HEAD:.env
cd $X && git rm :/.env
git -C $X rm .env
ROWS
rg_rows 2 "cd unresolved: harness" "harness infrastructure" <<'ROWS'
cd $PWD && echo x > .claude/settings.json
cd $PWD && mv scripts x
cd $X && git apply %AUX%/harness.patch
ROWS
# From a subdirectory, so only the repo's top gives the right path.
rg_shell 2 "cd unresolved: blob from the top of the repo" "$wt/src" 'cd $X && git show HEAD:secrets/key' "protected path"
rg_shell 2 "cd unresolved: patch from the top of the repo" "$wt/src" "cd \$X && git apply $aux/harness.patch" "harness infrastructure"
rg_rows 0 "cd unresolved: fine targets" "" <<'ROWS'
cd $PWD && echo x > src/app.py
cd $PWD && cat src/app.py
cd $X && echo x > /dev/null
(cd $X); echo x > src/app.py
cd $X && cd %AUX% && echo x > .env
ROWS
: > "$gb_log"
rg_shell 0 "cd unresolved: a pass is still logged" "$wt" 'cd $X && echo x > src/app.py'
grep -q 'unknown cwd for target: src/app.py' "$gb_log" && ok "guard-bash: review: cd unresolved: logged" \
  || bad "guard-bash: review: cd unresolved: logged"

# --- Criterion 8: wrappers ---
rg_rows 2 "wrappers" "denied" <<'ROWS'
sudo git push
sudo -n git push
sudo -u root git push
sudo -uroot git push
sudo --user root git push
sudo --user=root git push
sudo --us root git push
sudo -E -H git push
sudo -- git push
sudo FOO=1 git push
/usr/bin/sudo git push
doas git push
doas -n git push
doas -u root git push
setsid git push
setsid -w git push
setsid --fork git push
stdbuf -oL git push
stdbuf -o L git push
stdbuf -i0 -oL -e 0 git push
stdbuf --output L git push
stdbuf --output=L git push
stdbuf --o L git push
ionice git push
ionice -c 3 git push
ionice -c3 -n 7 git push
ionice --class idle git push
ionice --class idle --classdata 7 git push
ionice -t git push
setsid stdbuf -oL ionice -c3 sudo -u root doas git push
ROWS
rg_rows 2 "wrappers: reads and writes" "protected path" <<'ROWS'
sudo cat .env
doas cat .env
setsid cat .env
stdbuf -oL cat .env
ionice -c3 cat .env
sudo tee .env
sudo rm .env
ROWS
rg_rows 0 "wrappers: harmless" "" <<'ROWS'
sudo ls
sudo -l
doas ls
setsid ls
stdbuf -oL ls
ionice -c3 ls
ionice -p 1
ROWS

# --- Criterion 9: git config keys that run a program ---
rg_rows 2 "git config" "can run code" <<'ROWS'
git config core.pager sh
git config core.editor sh
git config diff.external sh
git config filter.x.clean sh
git config filter.x.smudge sh
git config filter.x.process sh
git config credential.helper sh
git config credential.https://example.com.helper sh
git config sequence.editor sh
git config gpg.program sh
git config gpg.ssh.program sh
git config gpg.format ssh
git config CORE.PAGER sh
git config Diff.External sh
git config --add core.pager sh
git config --global core.editor sh
git config --local filter.x.clean sh
git config --replace-all core.pager sh
git config set core.pager sh
git config --remove-section filter.x
git config --unset core.pager
git -c core.pager=sh log
git -c core.editor=sh commit
git -c diff.external=sh diff
git -c filter.x.clean=sh add -A
git -c credential.helper=sh fetch
git -c sequence.editor=sh rebase -i HEAD
git -c gpg.program=sh commit -S
git --config-env=core.pager=X log
ROWS
rg_rows 0 "git config: harmless" "" <<'ROWS'
git config core.pager
git config --get core.editor
git config --get diff.external
git config get credential.helper
git config --list
git config user.name x
git config diff.renames true
git config core.pagers x
git config filters.x y
git -c user.name=x log
git -c diff.renames=true diff
ROWS

# --- Criterion 10: git grep reads files on disk with --no-index ---
rg_rows 2 "git grep" "protected path" <<'ROWS'
git grep --no-index KEY .env
git grep --no-index KEY -- .env
git grep --no-index -e KEY .env
git grep --no-index -e KEY -- src/.env
git grep --no-index -n -A 2 KEY .env
git grep --no-index -f .env src/app.py
git grep --no-index --file .env src/app.py
git grep --no-index --max-depth 1 KEY .env
git -C src grep --no-index KEY .env
git grep --untracked KEY .env
ROWS
rg_rows 0 "git grep: harmless" "" <<'ROWS'
git grep KEY
git grep -n KEY -- src
git grep --no-index KEY src/app.py
git grep --no-index -e .env src/app.py
git grep --no-index .env src/app.py
git grep --no-index --threads 2 .env src/app.py
git grep --no-index --max-depth 1 .env src/app.py
ROWS

# --- Criterion 11: the template exemption stops at secrets/ ---
rg_rows 2 "secrets example" "protected path" <<'ROWS'
cat secrets/.env.example
cat secrets/.env.sample
cat secrets/.env.template
cat secrets/sub/.env.example
cat src/secrets/.env.example
grep x secrets/.env.example
cp secrets/.env.example src/app.py
ROWS
rg_rows 0 "secrets example: templates stay readable" "" <<'ROWS'
cat .env.example
cat .env.sample
cat src/.env.template
cat src/not-secrets/.env.example
ROWS

# --- Criterion 12: --text is not --textconv ---
rg_rev() { # rg_rev <expected-exit> <command> : as the reviewer role
  local err got
  err="$( unset HARNESS_MAINTAINER; export HARNESS_ROLE=reviewer
          bash_in "$wt" "$2" | "$BASH" "$gb_hook" 2>&1 >/dev/null )"
  got=$?
  if [ "$got" = "$1" ]; then ok "guard-bash: review: reviewer text: $2"
  else bad "guard-bash: review: reviewer text: $2 (want exit $1, got $got: $err)"; fi
}
rg_rev 0 'git diff --text'
rg_rev 0 'git diff --text main...HEAD'
rg_rev 0 'git show --text HEAD'
rg_rev 0 'git log -p --text'
rg_rev 2 'git diff --textconv'
rg_rev 2 'git diff --textco'
rg_rev 2 'git diff --textc'
rg_rev 2 'git show --textconv HEAD'
rg_rev 2 'git diff --tex'
rg_rev 2 'git diff --text --ext-diff'
# Decoding must not open the reviewer's list: the decoded word is judged like any other.
rg_rev 2 "git diff \$'--output=x'"
rg_rev 2 "git diff \$\"--output=x\""
rg_rev 2 "\$'rm' x"
rg_rev 2 "git diff \$'\\u0041'"
