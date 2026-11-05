# Sourced by run.sh: holes found by probing guard-bash (contract v02-guard-shell-gaps).
# Needs gb and gb_table from cases-guard-bash.sh, which sorts first. Rows are <cwd>, a tab, the
# command, and go to the real hook as real hook JSON. None of them ever runs. Leaves the fixture
# as it found it.

# Empty directories don't reach a worktree, and these rows need to see one on disk.
mkdir -p "$wt/src/billing" "$wt/src/tree" "$wt/lib"

# --- Criterion 1: a parent directory of a protected path counts as that path ---
gb_table 2 "gaps: parent dir" <<'ROWS'
wt	mv .claude x
wt	mv .claude/hooks x
wt	mv .claude/rules x
wt	mv .claude/skills/debug x
wt	mv scripts y
wt	mv tests y
wt	mv tests/harness y
wt	mv .git x
wt	mv secrets x
wt	cp -R x .claude
wt	cp -R x .claude/hooks
wt	cp -R x scripts
wt	cp -R x tests
wt	cp -R x tests/harness
wt	cp -r x secrets
wt	cp -a x .git
wt	cp --recursive x scripts
wt	cp -a x scripts
wt	cp --archive x scripts
wt	cp -R -t scripts x
wt	cp x .claude/
wt	cp x .claude
wt	mv x .claude
wt	mv src/tree scripts
wt	mv src/tree scripts/
wt	ln -s x .claude/
wt	echo x > .claude
wt	touch scripts
wt	cd src && mv ../.claude x
wt	cd scripts && mv ../scripts y
wt	mv src/hooks-link x
ROWS

# The repo itself is the parent of all of them, whichever way it's spelled
gb_table 2 "gaps: parent dir: whole repo" <<'ROWS'
wt	mv . ../x
wt	mv ../demo ../x
wt	mv %WT% %AUX%/stolen
wt	rm -rf .
wt	rm -rf ./
wt	rm -rf %WT%
wt	rm -rf ..
wt	rm -rf ../..
wt	rm -rf %FX%
wt	rm -rf /
wt	cd src && rm -rf ..
wt	cp -R x/. .
main	rm -rf .
main	mv . ../x
main	rm -rf .worktrees/demo
main	rm -rf .worktrees
out	rm -rf %WT%
out	mv %FX% x
ROWS

# --- Criterion 2: a trailing slash or . is the bare path, and cp x dir/ means dir/x ---
gb_table 2 "gaps: into dir" <<'ROWS'
wt	mv .claude/ x
wt	mv .claude/. x
wt	mv .claude// x
wt	mv .claude/hooks/ x
wt	mv scripts/ y
wt	mv scripts/. y
wt	mv tests/harness/ y
wt	mv secrets/ x
wt	cp x .claude/.
wt	cp x .claude/hooks/
wt	cp x .claude/hooks/.
wt	cp %AUX%/verify.sh scripts/
wt	cp %AUX%/verify.sh scripts/.
wt	cp %AUX%/verify.sh scripts
wt	cp %AUX%/verify.sh/ scripts
wt	cp %AUX%/verify.sh// scripts
wt	mv %AUX%/verify.sh scripts/
wt	cp %AUX%/.env src/
wt	cp %AUX%/.env src/.
wt	cp %AUX%/pay.py// src/billing/
wt	cp -R %AUX%/hooks/ .claude/
wt	cp -R %AUX%/x/. .claude
wt	cp -R %AUX%/x/ scripts
ROWS
gb_table 0 "gaps: into dir: what lands there is fine" <<'ROWS'
wt	cp x src/
wt	cp x src/.
wt	cp x scripts/
wt	cp x scripts/.
wt	cp x tests/
wt	mv %AUX%/x scripts/
wt	cp .claude/settings.json src/
ROWS

# --- Criterion 3: deleting or disabling ---
gb_table 2 "gaps: disable" <<'ROWS'
wt	rm .claude/hooks/guard-bash.sh
wt	rm -f .env
wt	rm -rf .claude
wt	rm -rf .claude/
wt	rm -r -- .claude
wt	rm -rf scripts
wt	rm -rf scripts/verify.sh
wt	rm -rf secrets
wt	rm -rf .git
wt	rm -rf tests/harness
wt	rm -rf src/billing
wt	/bin/rm -rf .claude
wt	command rm -rf .claude
wt	bash -c 'rm -rf .claude'
wt	rmdir .claude/hooks
wt	rmdir -p .claude/hooks
wt	unlink .claude/settings.json
wt	unlink scripts/verify.sh
wt	find .claude -delete
wt	find .claude/ -delete
wt	find scripts -name '*.sh' -delete
wt	find -L .claude -delete
wt	find -f .claude -delete
wt	find src .claude -delete
wt	find . -delete
wt	find . -name x -delete
wt	find -delete
wt	find .claude -exec rm {} +
wt	find .claude -exec /bin/rm -rf {} ;
wt	find .claude -type f -exec chmod -x {} +
wt	find .claude -execdir rmdir {} +
wt	chmod -x .claude/hooks/guard-bash.sh
wt	chmod 000 .claude/hooks/guard-bash.sh
wt	chmod u-x .claude/hooks/guard-bash.sh
wt	chmod a=,u=r .claude/hooks/guard-bash.sh
wt	chmod -w .claude/settings.json
wt	chmod -R 000 .claude
wt	chmod -R -x .claude/hooks
wt	chmod -Rv 000 .claude/hooks
wt	chmod 000 -R .claude
wt	chmod -- -x .claude/hooks/guard-bash.sh
wt	chmod 644 -- scripts/verify.sh
wt	chmod 000 src/app.py .claude/hooks/guard-bash.sh
wt	chmod --reference=src/app.py .claude/hooks/guard-bash.sh
wt	chmod --reference src/app.py .claude/hooks/guard-bash.sh
wt	chmod -R 000 src/billing
wt	chown me .claude/settings.json
wt	chown -R me:staff .claude
wt	chown --reference=src/app.py .claude/settings.json
wt	chown --reference src/app.py .claude/settings.json
wt	chown --from me you .claude/settings.json
wt	chgrp staff .claude/hooks
wt	git rm .claude/settings.json
wt	git rm -r .claude
wt	git rm -rf .claude/hooks
wt	git rm --cached scripts/verify.sh
wt	git rm -r .
wt	git rm -r :/.claude
wt	git rm -r ':(top).claude'
wt	git rm -r src/billing
wt	git -C src rm -r ../.claude
wt	git mv .claude x
wt	git mv scripts y
wt	git mv src/app.py .claude/hooks/a.sh
wt	git mv src/app.py scripts/verify.sh
wt	git mv -f src/app.py .claude/
main	rm src/app.py
main	chmod +x src/app.py
main	git rm src/app.py
main	git mv src/a src/b
ROWS

# --- Criterion 4: git writes a whole directory ---
gb_table 2 "gaps: git paths" <<'ROWS'
wt	git checkout HEAD~1 -- .claude
wt	git checkout HEAD~1 -- .claude/
wt	git checkout HEAD~1 -- .claude/hooks
wt	git checkout HEAD~1 .claude
wt	git checkout HEAD~1 -- scripts
wt	git checkout HEAD~1 -- tests/harness
wt	git checkout HEAD~1 -- .
wt	git checkout HEAD~1 -- :/.claude
wt	git checkout HEAD~1 :/.claude
wt	git checkout HEAD -- ':(top)scripts/verify.sh'
wt	git checkout -- .
wt	git checkout .
wt	git checkout .claude
wt	git checkout HEAD -- src/billing
wt	cd src && git checkout HEAD~1 -- ../.claude
wt	git restore .claude
wt	git restore .claude/
wt	git restore .claude/hooks
wt	git restore --source=HEAD~1 .claude
wt	git restore -s HEAD~1 scripts
wt	git restore tests/harness
wt	git restore .
wt	git restore :/.claude
wt	git restore -W .claude
wt	git restore src/billing
ROWS
gb_table 0 "gaps: git paths: what must pass" <<'ROWS'
wt	git checkout HEAD -- src
wt	git checkout HEAD~1 -- src/app.py
wt	git checkout HEAD -- :/src
wt	git restore src
wt	git restore :/src/app.py
wt	git restore --source=HEAD~1 src
wt	git restore --staged .claude
wt	git checkout task/demo
ROWS

# --- Criterion 5: writers that weren't known ---
gb_table 2 "gaps: other writers" <<'ROWS'
wt	rsync -a x/ .claude/
wt	rsync -a x .claude
wt	rsync -av --delete x/ scripts/
wt	rsync -a --exclude .git x/ .claude/hooks/
wt	rsync -e ssh -a x/ .claude/
wt	rsync -a x/ tests/harness/
wt	rsync -a x/ .
wt	rsync -a x/ secrets/
wt	rsync -a x/ .git/
wt	rsync -a .env %AUX%/y
wt	rsync -a --remove-source-files .claude/ %AUX%/y
wt	ditto x .claude
wt	tar -xf a.tar -C .claude
wt	tar -C .claude -xf a.tar
wt	tar xf a.tar -C .claude
wt	tar xzvf a.tgz -C scripts
wt	tar -x -f a.tar -Cscripts
wt	tar --extract --file a.tar --directory .claude
wt	tar --extract --file=a.tar --directory=.claude
wt	tar -xf a.tar -C src -C .claude
wt	cd src && tar -xf a.tar --dir=../.claude
wt	tar -xf a.tar -C secrets
wt	tar -xf a.tar -C src/billing
wt	cd .claude && tar -xf a.tar
wt	cd .claude/hooks && tar -xf a.tar
wt	tar -xf a.tar
wt	gtar -xf a.tar -C .claude
wt	bsdtar -xf a.tar -C .claude
wt	tar -xf .env -C src
wt	cd src && tar --extract --file a.tar --directory ../.claude
wt	tar -cf .claude/x.tar src
wt	tar -czf %AUX%/x.tgz .env
wt	tar czf %AUX%/x.tgz .env
wt	unzip a.zip -d .claude
wt	unzip -o a.zip -d scripts
wt	unzip -d .claude a.zip
wt	unzip a.zip -d.claude
wt	unzip a.zip -x b -d .claude
wt	unzip a.zip -d secrets
wt	cd .claude && unzip a.zip
wt	unzip a.zip
wt	ruby -pi -e 1 .claude/settings.json
wt	ruby -i -pe 1 .claude/settings.json
wt	ruby -i.bak -pe 1 .claude/settings.json
wt	ruby -pe 1 -i .env
wt	ruby -pi -e 1 src/app.py .claude/settings.json
wt	awk -i inplace 1 .claude/settings.json
wt	gawk -i inplace '{print}' .claude/settings.json
wt	gawk -iinplace 1 .claude/settings.json
wt	gawk --include=inplace 1 .claude/settings.json
wt	gawk --include inplace 1 .claude/settings.json
wt	gawk -i inplace -f prog.awk .claude/settings.json
wt	gawk -i inplace -v a=b 1 src/app.py .claude/settings.json
main	rsync -a x/ src/
main	tar -xf a.tar -C src
main	unzip a.zip -d src
main	ruby -pi -e 1 src/app.py
main	awk -i inplace 1 src/app.py
ROWS
gb_table 0 "gaps: other writers: what must pass" <<'ROWS'
wt	rsync -a src/ lib/
wt	rsync -a .claude/ %AUX%/backup/
wt	rsync -a x/ host:/srv/x
wt	rsync -a --exclude .env src/ lib/
wt	ditto src lib
wt	tar -xf a.tar -C src
wt	tar xf a.tar -C src
wt	tar --extract --file a.tar --directory src
wt	tar -xf a.tar -C %AUX%
wt	cd src && tar -xf a.tar
wt	tar -tf a.tar
wt	tar tf a.tar
wt	tar -xOf a.tar
wt	tar -czf %AUX%/x.tgz src
wt	tar -czf %AUX%/x.tgz .claude
wt	tar
wt	unzip a.zip -d src
wt	unzip a.zip -d %AUX%
wt	unzip -l a.zip
wt	unzip -p a.zip
wt	unzip -t a.zip
wt	ruby -pe 1 .claude/settings.json
wt	ruby -pi -e 1 src/app.py
wt	ruby x.rb
wt	awk 1 .claude/settings.json
wt	awk -i inplace 1 src/app.py
wt	gawk -i lib.awk 1 .claude/settings.json
ROWS

# --- Criterion 6: secrets read through git ---
gb_table 2 "gaps: git reads" <<'ROWS'
wt	git show HEAD:.env
wt	git show HEAD~1:.env
wt	git show main:.env
wt	git show HEAD:src/.env.local
wt	git show HEAD:secrets/token
wt	git show HEAD:secrets/a:b
wt	cd src && git show HEAD:secrets/token
wt	cd src && git show HEAD:../secrets/token
wt	git show HEAD:certs/client.pem
wt	git show :.env
wt	git show :0:.env
wt	git show HEAD:./.env
wt	git show --format=%h HEAD:.env
wt	git show HEAD:src/app.py HEAD:.env
wt	git -C src show HEAD:.env
wt	cd src && git show HEAD:.env
wt	cd src && git show HEAD:./.env.local
wt	cd src && git show HEAD:../.env
wt	git show 'HEAD^{/a:b}:.env'
wt	git cat-file -p HEAD:.env
wt	git cat-file blob HEAD:.env
wt	git cat-file --textconv HEAD:.env
wt	git cat-file -p HEAD:secrets/token
wt	git diff --no-index /dev/null .env
wt	git diff --no-index .env src/app.py
wt	git diff --no-index src/app.py .env
wt	git diff --no-index -- /dev/null secrets/token
wt	git diff --no-index --stat /dev/null src/.env.local
wt	git diff /dev/null .env
wt	git diff /dev/null %AUX%/.env
wt	git diff HEAD:.env HEAD~1:.env
out	git diff /dev/null .env
out	git diff --no-index /dev/null .env
ROWS
gb_table 0 "gaps: git reads: what must pass" <<'ROWS'
wt	git show HEAD:README.md
wt	git show HEAD:src/app.py
wt	git show HEAD:.env.example
wt	git show HEAD:src/envelope.py
wt	git show HEAD~1
wt	git show HEAD --stat
wt	git show --format=%h:%s HEAD
wt	git show --pretty=format:%s HEAD
wt	git cat-file -p HEAD
wt	git cat-file -t HEAD:src/app.py
wt	git cat-file -p HEAD:README.md
wt	git diff
wt	git diff --stat
wt	git diff main...HEAD
wt	git diff HEAD~1:src/app.py HEAD:src/app.py
wt	git diff --no-index src/app.py src/b.py
wt	git diff --no-index /dev/null .env.example
ROWS

# --- Criterion 7: git config that runs code or skips the hooks ---
gb_table 2 "gaps: git config" <<'ROWS'
wt	git config core.hooksPath /tmp/x
wt	git config core.hookspath /tmp/x
wt	git config CORE.HOOKSPATH /tmp/x
wt	git config --local core.hooksPath /tmp/x
wt	git config --global core.hooksPath /tmp/x
wt	git config --worktree core.hooksPath /tmp/x
wt	git config --add core.hooksPath /tmp/x
wt	git config --replace-all core.hooksPath /tmp/x
wt	git config --unset core.hooksPath
wt	git config --unset-all core.hooksPath
wt	git config set core.hooksPath /tmp/x
wt	git config unset core.hooksPath
wt	git config -f .git/config core.hooksPath /tmp/x
wt	git config --file=.git/config core.hooksPath /tmp/x
wt	git config core.fsmonitor /tmp/x
wt	git config --local core.fsmonitor /tmp/x
wt	git config core.sshCommand /tmp/x
wt	git config include.path /tmp/x
wt	git config includeIf.gitdir:/x.path /tmp/x
wt	git config alias.x '!sh'
wt	git config alias.st status
wt	git config ALIAS.st status
wt	git config --remove-section core
wt	git config --remove-section alias
wt	git config --rename-section alias x
wt	git config remove-section core
wt	git -C src config core.hooksPath /tmp/x
wt	git -c core.hooksPath=/tmp/x commit -m x
wt	git -c core.fsmonitor=/tmp/x status
wt	git -c core.sshCommand=/tmp/x fetch
wt	git -c alias.x='!sh' x
wt	git --config-env=core.hooksPath=V status
wt	git --config-env core.hooksPath=V status
wt	git config --file .claude/settings.json user.name x
wt	git config -f .env user.name x
wt	git config -f .env --list
wt	git config --file=.env --get x
wt	git config get -f .env x
ROWS
gb_table 0 "gaps: git config: what must pass" <<'ROWS'
wt	git config user.name x
wt	git config --local user.email a@example.invalid
wt	git config --global pull.rebase true
wt	git config core.autocrlf false
wt	git config set user.name x
wt	git config core.hooksPath
wt	git config --get core.hooksPath
wt	git config --get core.hooksPath pattern
wt	git config --get-all alias.x
wt	git config --get-regexp '^alias'
wt	git config get core.hooksPath
wt	git config list
wt	git config --list
wt	git config --list --show-origin
wt	git config -l
wt	git config -f .claude/settings.json --list
wt	git config get -f .claude/settings.json user.name
wt	git -c user.name=x commit -m y
wt	git -c a=b status
ROWS

# --- Criterion 8: normal work still passes ---
gb_table 0 "gaps: must pass" <<'ROWS'
wt	mv src/a src/b
wt	mv src/tree src/other
wt	mv src/tree lib
wt	mv %AUX%/a %AUX%/b
wt	mv scripts/old.sh scripts/new.sh
wt	cp -R src lib
wt	cp -R src lib2
wt	cp -R src %AUX%/out
wt	cp -R .claude %AUX%/backup
wt	cp scripts/verify.sh %AUX%/v
wt	chmod +x src/run.sh
wt	chmod -x src/run.sh
wt	chmod 644 src/app.py
wt	chmod -R u+w src/tree
wt	chmod +x scripts/new.sh
wt	chmod +x %AUX%/x.sh
wt	chown me src/app.py
wt	chgrp staff src/app.py
wt	git mv src/a src/b
wt	git rm src/old.py
wt	git rm -r src/tree
wt	git rm --cached src/old.py
wt	rm src/old.py
wt	rm -rf src/tree
wt	rm -rf %AUX%/x
wt	rmdir src/tree
wt	unlink src/old.py
wt	find src -name '*.pyc' -delete
wt	find src -exec rm {} +
wt	find . -name '*.py'
wt	find .claude -type f
wt	find . -type f -exec grep x {} +
wt	find -f src -name x
wt	find -f src -delete
wt	find -L src -name x -delete
wt	echo x > .claude/agent-memory/note.md
ROWS

# Best effort stays best effort: these pass and leave a line in the log
: > "$gb_log"
gb_table 0 "gaps: unresolved" <<'ROWS'
wt	rm -rf $X
wt	rm -rf .cl*
wt	chmod 000 $X
wt	git show HEAD:$X
wt	git rm -r ':!src'
wt	rsync -a x/ $X/
wt	echo HEAD:.env | git cat-file --batch
ROWS
for needle in 'unresolved target: $X' 'unresolved target: .cl*' 'unresolved pathspec: :!src' 'git cat-file from stdin'; do
  if grep -qF "$needle" "$gb_log"; then ok "guard-bash: gaps: logged: $needle"; else bad "guard-bash: gaps: logged: $needle"; fi
done

# Edit and Write only ever name files. What changed for them: files directly under .claude.
guard 2 "gaps: write: file directly under .claude" "$wt/.claude/HARNESS_VERSION"
guard 2 "gaps: write: new file directly under .claude" "$wt/.claude/x"
guard 0 "gaps: write: tool state under .claude"    "$wt/.claude/agent-memory/note.md"
guard 0 "gaps: write: new script"                  "$wt/scripts/new.sh"
guard 0 "gaps: write: new test"                    "$wt/tests/test_new.py"

# --- Criterion 9: maintainer mode opens the harness items and nothing else ---
while IFS= read -r row; do
  [ -n "$row" ] || continue
  par_begin; gb 0 "gaps: maintainer: allowed: $row" "$wt" "$row" "" maint > "$PF" & par_end $!
done <<'ROWS'
mv .claude x
mv .claude/hooks x
mv scripts y
mv tests/harness y
cp -R x .claude
cp x .claude/
rm -rf .claude
rmdir .claude/hooks
unlink .claude/settings.json
find .claude -delete
chmod -x .claude/hooks/guard-bash.sh
chown me .claude/settings.json
git rm -r .claude
git mv .claude x
git checkout HEAD~1 -- .claude
git restore .claude
rsync -a x/ .claude/
tar -xf a.tar -C .claude
unzip a.zip -d .claude
ruby -pi -e 1 .claude/settings.json
awk -i inplace 1 .claude/settings.json
git config core.hooksPath .githooks
git -c core.hooksPath=/tmp/x status
ROWS
par_flush
while IFS= read -r row; do
  [ -n "$row" ] || continue
  par_begin; gb 2 "gaps: maintainer: never: $row" "$wt" "$row" "" maint > "$PF" & par_end $!
done <<'ROWS'
mv .git x
rm -rf .git
find .git -delete
chmod -R 000 .git
rsync -a x/ .git/
rm -rf .
mv . ../x
mv secrets x
rm -rf secrets
cp -R x secrets
cp x secrets/
find secrets -delete
chmod 000 .env
rm .env
rm .claude/settings.local.json
git rm .env
git rm -r secrets
git checkout HEAD -- secrets
rsync -a x/ secrets/
tar -xf a.tar -C secrets
unzip a.zip -d secrets
awk -i inplace 1 .env
ruby -pi -e 1 .env
git show HEAD:.env
git cat-file -p HEAD:.env
git diff --no-index /dev/null .env
ROWS
par_flush

# The reasons say what to do next
gb 2 "gaps: message: harness parent"   "$wt" 'mv .claude x'          "harness infrastructure"
gb 2 "gaps: message: secrets parent"   "$wt" 'rm -rf secrets'        "protected path (secrets)"
gb 2 "gaps: message: git parent"       "$wt" 'rm -rf .git'           "git internals"
gb 2 "gaps: message: whole repo"       "$wt" 'rm -rf .'              "whole repository"
gb 2 "gaps: message: another worktree" "$aux" "rm -rf $wt"          "whole repository"
gb 2 "gaps: message: git read"         "$wt" 'git show HEAD:.env'    "Don't read it"
gb 2 "gaps: message: git config"       "$wt" 'git config core.hooksPath x' "! prefix"

# A contract's globs judge the file, not the directory it lands in
cp "$wt/.agent/contracts/demo.md" "$aux/demo.md.gaps"
echo demo > "$wt/.agent/state/active-task"
printf '# Contract: demo\n## Target files\n- src/app.py\n' > "$wt/.agent/contracts/demo.md"
gb 0 "gaps: contract: cp into a directory, file named"  "$wt" 'cp x/app.py src/'
gb 2 "gaps: contract: cp into a directory, other file"  "$wt" 'cp x/other.py src/' "outside the contract"
gb 0 "gaps: contract: cp -R into a directory, file named" "$wt" 'cp -R x/app.py src/'
gb 2 "gaps: contract: rsync elsewhere"                  "$wt" 'rsync -a x/ lib/' "outside the contract"
gb 2 "gaps: contract: delete outside"                   "$wt" 'rm src/other.py' "outside the contract"
gb 2 "gaps: contract: chmod outside"                    "$wt" 'chmod +x src/other.py' "outside the contract"
rm -f "$wt/.agent/state/active-task"
cp "$aux/demo.md.gaps" "$wt/.agent/contracts/demo.md"

rmdir "${wt:?}/src/billing" "${wt:?}/src/tree" "${wt:?}/lib"
