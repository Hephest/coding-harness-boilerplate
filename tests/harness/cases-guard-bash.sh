# Sourced by run.sh: shell guard cases (contract v02-guard-shell).
# Commands live in the ROWS tables as data, one per line: <cwd>, a tab, the command.
#   cwd: wt = task worktree, main = main checkout, out = outside any repo
#   %NL% = newline, %TAB% = tab, %FX% %WT% %AUX% = fixture paths
# Each row goes to the hook as real hook JSON. Leaves the fixture as it found it.

gb_hook="$fx/.claude/hooks/guard-bash.sh"
gb_log="$fx/.agent/state/guard-bash.log"
gb_fin="$aux/finish.json"   # the input file the must-finish cases hand to the hook

# json_str <text> : a JSON string. Pure bash, so a row can't break out of its JSON whatever it holds.
# For rows only: ${x//} is quadratic on bash 3.2, and 300KB takes minutes. See gb_big.
# Bash 5.2 gives a backslash or & in a replacement a meaning (patsub_replacement), while bash 3.2
# keeps the quotes of a quoted replacement. No spelling is right on both, so switch the feature off
# (3.2 has no such option; the error is ignored) and keep the replacements bare.
shopt -u patsub_replacement 2>/dev/null
json_str() {
  local s="$1" q='"' b='\'
  s="${s//"$b"/$b$b}"
  s="${s//$q/$b$q}"
  s="${s//$'\n'/${b}n}"
  s="${s//$'\t'/${b}t}"
  printf '"%s"' "$s"
}
bash_in() { # bash_in <cwd> <command>
  printf '{"tool_name":"Bash","cwd":%s,"tool_input":{"command":%s}}' "$(json_str "$1")" "$(json_str "$2")"
}

# --- Running rows side by side ---
# Rows only read the fixture and the hook is a fresh process per row, so rows run PAR_MAX at a time.
# Each job writes its PASS/FAIL lines to its own file. They are printed, and counted, in the order
# the jobs were started, so the output is the same as a serial run and a failure still names its row.
# One job per core, 16 at most: the big inputs have a 15 second limit, which a starved job would miss.
PAR_MAX="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
case "$PAR_MAX" in ''|*[!0-9]*|0) PAR_MAX=2 ;; esac
[ "$PAR_MAX" -gt 16 ] && PAR_MAX=16
PAR_SEQ=0; PAR_HEAD=0; PAR_TAIL=0; PAR_PIDS=(); PAR_FILES=(); PF=""; PD=""
par_reap() { # the oldest job: wait for it, then replay its lines
  local line st n=0
  wait "${PAR_PIDS[$PAR_HEAD]}" 2>/dev/null; st=$?
  while IFS= read -r line; do
    case "$line" in "PASS  "*) pass=$((pass + 1)); n=$((n + 1)) ;; "FAIL  "*) fail=$((fail + 1)); n=$((n + 1)) ;; esac
    printf '%s\n' "$line"
  done < "${PAR_FILES[$PAR_HEAD]}"
  # A job that was killed or crashed has no say in the count above, so "0 failed" would still print.
  if [ "$st" != 0 ] || [ "$n" = 0 ]; then
    fail=$((fail + 1)); echo "FAIL  par: job $PAR_HEAD died (exit $st, $n result lines)"
  fi
  PAR_HEAD=$((PAR_HEAD + 1))
}
par_begin() { # sets PF (the job's output file) and PD (a private dir name) once a slot is free
  while [ $((PAR_TAIL - PAR_HEAD)) -ge "$PAR_MAX" ]; do par_reap; done
  PAR_SEQ=$((PAR_SEQ + 1))
  PF="$aux/par.$((PAR_SEQ % PAR_MAX))"; PD="$aux/mf.$PAR_SEQ"
}
par_end() { PAR_PIDS[$PAR_TAIL]="$1"; PAR_FILES[$PAR_TAIL]="$PF"; PAR_TAIL=$((PAR_TAIL + 1)); }
par_flush() { while [ "$PAR_HEAD" -lt "$PAR_TAIL" ]; do par_reap; done; }

gb_cwd() {
  case "$1" in wt) echo "$wt" ;; main) echo "$fx" ;; out) echo "$aux" ;; esac
}
gb_expand() {
  local s="$1"
  s="${s//%NL%/$'\n'}"; s="${s//%TAB%/$'\t'}"
  s="${s//%FX%/$fx}"; s="${s//%WT%/$wt}"; s="${s//%AUX%/$aux}"
  printf '%s' "$s"
}

# gb <expected-exit> <name> <cwd> <command> [text stderr must contain] [maintainer]
gb() {
  local want="$1" name="$2" cwd="$3" cmd="$4" needle="${5:-}" maint="${6:-}" err got
  err="$( unset HARNESS_MAINTAINER HARNESS_ROLE
          [ -n "$maint" ] && export HARNESS_MAINTAINER=1
          bash_in "$cwd" "$cmd" | "$BASH" "$gb_hook" 2>&1 >/dev/null )"
  got=$?
  if [ "$got" != "$want" ]; then bad "guard-bash: $name (want exit $want, got $got: $err)"
  elif [ -n "$needle" ] && [[ "$err" != *"$needle"* ]]; then bad "guard-bash: $name (stderr lacks '$needle': $err)"
  else ok "guard-bash: $name"; fi
}

# gb_raw <expected-exit> <name> <PATH for the hook> <bash binary> <raw stdin> [needle]
gb_raw() {
  local want="$1" name="$2" path="$3" sh="$4" input="$5" needle="${6:-}" err got
  err="$( unset HARNESS_MAINTAINER HARNESS_ROLE
          printf '%s' "$input" | PATH="$path" "$sh" "$gb_hook" 2>&1 >/dev/null )"
  got=$?
  if [ "$got" != "$want" ]; then bad "guard-bash: $name (want exit $want, got $got: $err)"
  elif [ -n "$needle" ] && [[ "$err" != *"$needle"* ]]; then bad "guard-bash: $name (stderr lacks '$needle': $err)"
  else ok "guard-bash: $name"; fi
}

gb_row() { gb "$1" "$2 [$3]: $4" "$(gb_cwd "$3")" "$(gb_expand "$4")"; }
# gb_table <expected-exit> <label> : reads ROWS from stdin
gb_table() {
  local want="$1" label="$2" where cmd
  while IFS=$'\t' read -r where cmd; do
    case "$where" in ''|\#*) continue ;; esac
    par_begin
    gb_row "$want" "$label" "$where" "$cmd" > "$PF" &
    par_end $!
  done
  par_flush
}

# A command that holds every awkward character must survive the trip into the hook unchanged.
tricky=$'a"b\\c\td\ne\'f$g`h'
if command -v jq >/dev/null 2>&1; then
  [ "$(bash_in "$wt" "$tricky" | jq -r .tool_input.command)" = "$tricky" ] \
    && ok "guard-bash: json_str round-trips" || bad "guard-bash: json_str round-trips"
fi

# Fixtures for the rows
cat > "$aux/harness.patch" <<'PATCH'
diff --git a/.claude/hooks/guard-write.sh b/.claude/hooks/guard-write.sh
index 1111111..2222222 100755
--- a/.claude/hooks/guard-write.sh
+++ b/.claude/hooks/guard-write.sh
@@ -1 +1 @@
-old
+new
PATCH
cat > "$aux/plain.patch" <<'PATCH'
--- old/.env	2026-01-01 00:00:00
+++ new/.env	2026-01-02 00:00:00
@@ -1 +1 @@
-old
+new
PATCH
cat > "$aux/rename.patch" <<'PATCH'
diff --git a/src/app.py b/.claude/settings.json
similarity index 100%
rename from src/app.py
rename to .claude/settings.json
PATCH
cat > "$aux/ok.patch" <<'PATCH'
diff --git a/src/app.py b/src/app.py
index 1111111..2222222 100644
--- a/src/app.py
+++ b/src/app.py
@@ -1,4 +1,4 @@
--- x/.env
 a removed line and an added one that look like headers, but aren't a pair
+++ y/.env
 keep
PATCH

# --- Criterion 1: redirects and known write commands go through the policy ---
gb_table 2 "must-block: write" <<'ROWS'
wt	echo x > .env
wt	echo x >> .env
wt	echo x >| .env
wt	echo x &> .env
wt	echo x &>> .env
wt	echo x >& .env
wt	echo x 2> .env
wt	echo x 2>> .env
wt	echo x>.env
wt	echo x <> .env
wt	> .env
wt	: > .env
wt	echo "x" > ".env"
wt	echo x > '.env'
wt	echo x > ./src/../.env
wt	echo x > src/env-link
wt	echo x > src/hooks-link/a.sh
wt	echo x > .claude/hooks/guard-write.sh
wt	echo x > CLAUDE.md
wt	echo x > .git/config
wt	cat > .env <<'EOF'%NL%x%NL%EOF
wt	cat <<EOF > .env%NL%x%NL%EOF
wt	tee .env
wt	echo x | tee -a .claude/settings.json
wt	echo x | tee src/a.py .env
wt	cp src/app.py .env
wt	cp src/app.py .claude/hooks/
wt	cp src/app.py .claude/hooks
wt	cp -r src/app.py src/ .claude/hooks/
wt	cp -t .claude/hooks src/app.py
wt	cp --target-directory=.claude/hooks src/app.py
wt	mv src/app.py .env
wt	mv .claude/hooks/guard-write.sh %AUX%/stolen
wt	mv .claude/hooks %AUX%/stolen
wt	mv -f src/app.py .claude/settings.json
wt	install src/app.py .env
wt	install -m 755 src/app.py .claude/hooks/a.sh
wt	install -d .claude/hooks/new
wt	ln -s src/app.py .env
wt	ln src/app.py .claude/hooks/a.sh
wt	ln -sf src/app.py .claude/settings.json
wt	dd if=/dev/zero of=.env
wt	dd of=.claude/settings.json if=src/app.py bs=1
wt	truncate -s 0 .env
wt	truncate --size 0 .claude/settings.json
wt	touch .env
wt	touch -t 202601010000 .claude/settings.json
wt	sed -i 's/a/b/' .env
wt	sed -i '' 's/a/b/' .claude/settings.json
wt	sed -i.bak 's/a/b/' .claude/settings.json
wt	sed -i .bak 's/a/b/' .claude/settings.json
wt	sed -Ei 's/a/b/' .claude/settings.json
wt	sed -i -e 's/a/b/' -e 's/c/d/' .claude/settings.json
wt	sed 's/a/b/' -i .claude/settings.json
wt	sed 's/a/b/' -i .env
wt	sed -e 's/a/b/' -i .env
wt	sed -e 's/a/b/' -i .gitignore .env
wt	sed -i .env -e 's/a/b/'
wt	sed -i .claude/settings.json -e 's/a/b/'
wt	sed -i .env -e 's/a/b/' src/app.py
wt	sed --in-place 's/a/b/' .claude/settings.json
wt	sed --in-place=.bak -e 's/a/b/' .claude/settings.json
wt	perl -i -pe 's/a/b/' .claude/settings.json
wt	perl -pi -e 's/a/b/' .claude/settings.json
wt	perl -i.bak -pe 's/a/b/' .claude/settings.json
wt	perl -pi -e 's/a/b/' src/app.py .claude/settings.json
wt	git apply %AUX%/harness.patch
wt	git apply --index %AUX%/harness.patch
wt	git apply %AUX%/plain.patch
wt	git apply %AUX%/rename.patch
wt	git -C src apply %AUX%/harness.patch
wt	git checkout -- .claude/hooks/guard-write.sh
wt	git checkout HEAD -- .claude/settings.json
wt	git checkout main -- src/app.py .env
wt	git checkout HEAD .claude/hooks/guard-write.sh
wt	git checkout .claude/hooks/guard-write.sh
wt	git restore .claude/hooks/guard-write.sh
wt	git restore --source=HEAD~1 .claude/settings.json
wt	git restore --source HEAD~1 .claude/settings.json
wt	git restore -s HEAD .claude/settings.json
wt	git restore --staged --worktree .claude/settings.json
wt	git restore -SW .claude/settings.json
main	echo x > src/app.py
main	echo x | tee src/app.py
main	cp .gitignore src/app.py
main	touch src/new.py
main	sed -i 's/a/b/' src/app.py
main	git checkout -- src/app.py
main	git restore src/app.py
main	git apply %AUX%/ok.patch
ROWS

# --- Criterion 2: reads of secrets ---
gb_table 2 "must-block: read" <<'ROWS'
wt	cat .env
wt	cat ./.env
wt	cat src/.env.local
wt	cat a/b/.env.prod
wt	cat src/app.py .env
wt	cat secrets/token
wt	cat certs/client.pem
wt	cat certs/client.key
wt	cat certs/client.p12
wt	cat home/id_rsa
wt	cat .npmrc
wt	cat .netrc
wt	cat src/env-link
wt	cat < .env
wt	wc -l < .env
wt	while read l; do echo "$l"; done < .env
wt	head -n 5 .env
wt	tail -f .env
wt	less .env
wt	more .env
wt	tac .env
wt	nl .env
wt	od -c .env
wt	xxd .env
wt	hexdump .env
wt	strings .env
wt	base64 .env
wt	sort .env
wt	uniq .env
wt	cut -d= -f2 .env
wt	diff .env src/app.py
wt	source .env
wt	. .env
wt	grep FOO .env
wt	grep -e FOO .env
wt	grep -n -A 3 FOO .env
wt	grep -f .env src/app.py
wt	egrep FOO .env
wt	rg FOO .env
wt	rg -e FOO .env
wt	sed -n 1p .env
wt	sed -e 1p .env
wt	awk '{print}' .env
wt	awk -F= '{print $2}' .env
wt	cp .env %AUX%/copy
wt	cp .env.local %AUX%/copy
wt	mv .env %AUX%/copy
wt	ln .env %AUX%/hardlink
wt	dd if=.env of=%AUX%/copy
out	cat %WT%/.env
out	cat .env
ROWS

# --- Criterion 3: denied git forms ---
gb_table 2 "must-block: git" <<'ROWS'
wt	git add -f x
wt	git add x -f
wt	git add -Af
wt	git add -fA
wt	git add -A -f
wt	git add --force x
wt	git add x --force
wt	git add --forc x
wt	git add --f x
wt	git -C . add -f x
wt	git -c a=b add -f x
wt	/usr/bin/git add -f x
wt	git push
wt	git push origin main
wt	git -C . push
wt	git -C /tmp push
wt	/usr/bin/git push
wt	git -c a=b push
wt	git -c a=b reset
wt	git -c a=b reset --hard
wt	git reset --soft HEAD~1
wt	git reset
wt	git --no-pager push
wt	git --git-dir=.git push
wt	git --git-dir .git --work-tree . push
wt	git -C . -c a=b -C . push
ROWS

# Every wrapper and every way to chain or nest a command reaches the same inspection
gb_table 2 "must-block: form" <<'ROWS'
wt	FOO=1 git push
wt	FOO=1 BAR="a b" git push
wt	env git push
wt	env FOO=1 git push
wt	env -i FOO=1 git push
wt	env -u FOO git push
wt	/usr/bin/env git push
wt	command git push
wt	command -p git push
wt	nohup git push
wt	nice git push
wt	nice -n 5 git push
wt	nice -5 git push
wt	time git push
wt	time -p git push
wt	timeout 5 git push
wt	timeout -k 1 5 git push
wt	timeout --preserve-status 5 git push
wt	timeout -s KILL 5 git push
wt	exec git push
wt	echo main | xargs git push
wt	echo x | xargs -n 1 git add -f
wt	echo x | xargs -I{} git add -f {}
wt	echo x | xargs -0 -I {} git add -f {}
wt	env FOO=1 nice -n 5 nohup timeout 5 git push
wt	true && git push
wt	true || git push
wt	true; git push
wt	true | git push
wt	true |& git push
wt	true & git push
wt	true%NL%git push
wt	true \%NL%  && git push
wt	(git push)
wt	( cd src; git push )
wt	{ git push; }
wt	if true; then git push; fi
wt	if git push; then true; fi
wt	while true; do git push; done
wt	for i in 1 2; do git push; done
wt	case x in x) git push ;; esac
wt	! git push
wt	f() { git push; }
wt	echo $(git push)
wt	echo "$(git push)"
wt	echo "a $(echo "b $(git push)") c"
wt	echo `git push`
wt	echo "`git push`"
wt	cat <(git push)
wt	echo x > >(git push)
wt	g'i't push
wt	"git" push
wt	g\it push
wt	git 'push'
wt	cat <<'EOF'%NL%body%NL%EOF%NL%git push
wt	cat <<-EOF%NL%%TAB%body%NL%%TAB%EOF%NL%git push
wt	cat <<A <<B%NL%a%NL%A%NL%b%NL%B%NL%git push
wt	cat <<EOF%NL%EOF%NL%git push
wt	cat <<EOF%NL%notEOF%NL%EOFnot%NL%EOF%NL%git push
wt	echo "don't"; git push
wt	echo 'a'"b"; git push
wt	echo hi # comment%NL%git push
wt	sh -c 'cat .env'
wt	bash -c 'echo x > .env'
wt	bash -c "git push"
wt	bash -lc 'git push'
wt	bash -ec 'git push'
wt	bash -o pipefail -c 'git push'
wt	bash --norc -c 'git push'
wt	/bin/sh -c 'git push'
wt	zsh -c 'git push'
wt	sh -c 'true && cat .env'
wt	sh -c "cd src && cat .env"
wt	eval 'cat .env'
wt	eval git push
wt	eval "echo x > .env"
wt	eval 'cd src'; cat .env
ROWS

# --- Criterion 5: cd moves where relative targets resolve, .cwd is where they start ---
gb_table 2 "must-block: cd" <<'ROWS'
wt	cd src && cat .env
wt	cd src && echo x > .env
wt	cd src; echo x > ../.env
wt	cd .claude/hooks && echo x > a.sh
wt	cd .claude && cd hooks && echo x > a.sh
wt	cd -P .claude/hooks && echo x > a.sh
wt	pushd .claude/hooks && echo x > a.sh
wt	cd ../.. && echo x > src/app.py
wt	cd %FX% && echo x > src/app.py
wt	cd %FX%/src && echo x > app.py
wt	(cd .claude/hooks && echo x > a.sh)
wt	(cd src); cat .env
wt	git -C .claude/hooks restore guard-write.sh
wt	git -C .claude checkout -- hooks/guard-write.sh
main	cd .worktrees/demo && cat .env
main	cd .worktrees/demo && echo x > .claude/hooks/a.sh
out	cd %WT% && echo x > .env
out	cd %FX% && echo x > src/app.py
ROWS

# --- Criteria 2 and 6: what must keep working ---
gb_table 0 "must-pass" <<'ROWS'
wt	echo "a > .env"
wt	echo 'a > .env'
wt	echo a \> .env
wt	echo "a | git push"
wt	echo 'a; git push'
wt	echo "git push && cat .env"
wt	echo hi # > .env
wt	echo hi # git push
wt	echo .env
wt	printf '%s\n' .env
wt	echo a#b
wt	cat <<'EOF'%NL%> .env%NL%git push%NL%cat .env%NL%EOF
wt	cat <<EOF%NL%> .env%NL%git push%NL%EOF
wt	cat <<-EOF%NL%%TAB%> .env%NL%%TAB%EOF
wt	cat <<EOF | tail -n 1%NL%git push%NL%EOF
wt	cat > src/new.py <<'EOF'%NL%open('.env')%NL%git push%NL%EOF
wt	cat <<< '> .env'
wt	git commit -m "fix .env loading"
wt	git commit -m 'a; b > c | d && e'
wt	git commit -m "a && b; c > .env | d (e) $HOME"
wt	git commit -m 'read .env, then git push'
wt	git commit -m "$(cat <<'EOF'%NL%don't touch .env > x (really) "quoted"%NL%%NL%git push is denied%NL%EOF%NL%)"
wt	git commit -am "line one%NL%line two > .env"
wt	claude -p "read .env and summarise it"
wt	scripts/herdr-sub.sh run reviewer "check .env > handling; git push"
wt	git checkout main
wt	git checkout task/demo
wt	git checkout -b task/new
wt	git checkout -b task/new main
wt	git checkout -B task/new
wt	git checkout -
wt	git switch task/demo
wt	git switch -c task/new
wt	echo x > /dev/null
wt	echo x >/dev/null 2>&1
wt	echo x 2>/dev/null
wt	echo x &>/dev/null
wt	echo x > /dev/stdout
wt	echo x > /dev/stderr
wt	echo x > /dev/fd/2
wt	echo x >&2
wt	echo x 1>&2
wt	echo x 2>&1
wt	echo x 2>&-
wt	exec 3>&-
wt	exec 3<&0
wt	scripts/verify.sh 2>&1 | tail
main	scripts/verify.sh 2>&1 | tail
main	echo x >&2
main	echo x 2>&1
main	echo x 2>&-
main	exec 3>&-
main	echo x | tee 2>/dev/null
wt	scripts/verify.sh 2>&1 | tail -n 20
wt	cat /dev/null > /dev/null
out	echo x > %AUX%/out.txt
wt	echo x > %AUX%/out.txt
wt	echo x >> %AUX%/out.txt
wt	cp src/app.py %AUX%/copy
wt	mv %AUX%/a %AUX%/b
wt	tee %AUX%/out.txt
wt	touch %AUX%/out.txt
wt	sed -i 's/a/b/' %AUX%/out.txt
main	echo x > %AUX%/out.txt
main	cp src/app.py %AUX%/copy
wt	cat .env.example
wt	cat .env.sample
wt	cat .env.template
wt	cat src/.env.example
wt	cat < .env.example
wt	head .env.sample
wt	grep FOO .env.template
wt	cp .env.example %AUX%/copy
wt	cp .env.example src/config.example
wt	sed -n 1p .env.example
wt	grep -r '.env' src
wt	grep '\.env' README.md
wt	grep .env README.md
wt	grep -c .env README.md
wt	grep -A 3 .env README.md
wt	rg '.env'
wt	rg '.env' src
wt	sed 's/.env/x/' README.md
wt	sed -n '/\.env/p' README.md
wt	awk '/.env/' README.md
wt	ls .env
wt	ls -la .env*
wt	test -f .env
wt	[ -f .env ]
wt	[[ -f .env ]]
wt	[[ a > b ]]
wt	[[ a < b ]]
main	[[ a > b ]]
main	[[ .env < b ]]
wt	find . -name .env
wt	git log --oneline -- .env
wt	git diff .env.example
wt	git status
wt	git show HEAD
wt	git add -A
wt	git add .
wt	git add src/app.py
wt	git add -- -f
wt	git add -u
wt	git add --chmod=+x scripts/x.sh
wt	git add -p
wt	git commit --amend --no-edit
wt	git worktree add -b task/x .worktrees/x HEAD
main	git worktree add -b task/x .worktrees/x HEAD
main	echo x > .agent/contracts/x.md
main	cp .agent/contracts/x.md .worktrees/demo/.agent/contracts/
main	echo demo > .worktrees/demo/.agent/state/active-task
main	printf 'demo\n' > .worktrees/demo/.agent/state/active-task
wt	echo demo > .agent/state/active-task
main	echo '| x |' >> .agent/lessons.md
main	cat >> .agent/lessons.md <<'EOF'%NL%| row |%NL%EOF
main	cat > .agent/receipts/x.md <<'EOF'%NL%done%NL%EOF
main	cat src/app.py
main	sed -n 1p src/app.py
main	perl -pe 's/a/b/' src/app.py
main	git restore --staged src/app.py
main	git apply --check %AUX%/ok.patch
main	git apply --stat %AUX%/ok.patch
wt	git apply %AUX%/ok.patch
wt	echo x > src/new.py
wt	sed -i 's/a/b/' src/app.py
wt	sed -i '' 's/a/b/' src/app.py
wt	sed -i .bak 's/a/b/' src/app.py
wt	sed -i .bak -e 's/a/b/' src/app.py
wt	touch src/new.py
wt	git checkout -- src/app.py
wt	git restore src/app.py
wt	(( 1 > 0 ))
wt	echo $(( 1 > 0 ))
wt	echo $((1<<2))
wt	bash -c 'echo hi'
wt	bash scripts/x.sh
wt	sh -c 'echo "a > .env"'
wt	eval 'echo hi'
wt	FOO=bar npm test
wt	FOO='a > .env' true
wt	/usr/bin/env python3 x.py
wt	(cd .claude/hooks) ; echo x > a.sh
wt	(cd src) && echo x > new.py
wt	echo $(cd .claude/hooks; pwd); echo x > a.sh
wt	echo `cd .claude/hooks`; echo x > a.sh
wt	bash -c 'cd .claude/hooks'; echo x > a.sh
wt	git -C .claude/hooks status; echo x > a.sh
main	cd .worktrees/demo && echo x > src/new.py
main	cd .worktrees/demo && git commit -m x
main	cd %WT% && echo x > src/new.py
wt	cd src && cat ../.env.example
wt	cd %AUX% && echo x > .claude
wt	python -c "print(open('.env').read())"
wt	node -e "require('fs').readFileSync('.env')"
ROWS

# A directory of secrets, for real: the check looks at what's on disk.
mkdir -p "$wt/secrets"
gb 2 "must-block: read: copying a secrets directory" "$wt" "cp -r secrets $aux/copy"
rmdir "$wt/secrets"

# Best effort: what can't be resolved passes, and leaves a line in the log.
: > "$gb_log"
gb_table 0 "must-pass: unresolved" <<'ROWS'
wt	echo x > $F
wt	echo x > "$HOME/.env"
wt	echo x > `pick`
wt	echo x > $(pick)
wt	cat .en*
wt	cat .en?
wt	cat .en[v]
wt	cat {.env,x}
wt	cp src/app.py $DEST
wt	cd "$X" && echo x > .env
wt	cd - && cat .env
wt	$EDITOR .env
wt	bash -c "bash -c 'cat .env'"
wt	echo x | git apply
wt	git apply %AUX%/missing.patch
ROWS
for needle in 'unresolved target: $F' 'unknown cwd for target: .env' 'unresolved command: $EDITOR' \
              'shell string nested too deep' 'git apply from stdin' 'no such patch'; do
  if grep -qF "$needle" "$gb_log"; then ok "guard-bash: logged: $needle"; else bad "guard-bash: logged: $needle"; fi
done

# --- Criterion 7: bad input blocks, a command it can't lex passes and is logged ---
gb_raw 2 "bad json: malformed"           "$PATH" "$BASH" '{"tool_input":'  "install jq"
gb_raw 2 "bad json: no reader"           "$(tool_dir gb-bare cat dirname)" "$BASH" "$(bash_in "$wt" 'echo hi')" "install jq"
gb_raw 2 "bad json: no command"          "$PATH" "$BASH" '{"tool_name":"Bash","tool_input":{}}' "names no command"
gb_raw 0 "bad json: empty stdin"         "$PATH" "$BASH" ""

: > "$gb_log"
for row in 'echo "unterminated' "echo 'unterminated" 'echo $(unterminated' '(unterminated' 'echo `unterminated' \
           'echo ${unterminated' "echo \$'unterminated" 'echo "$(echo "unterminated)"'; do
  gb 0 "unlexable: $row" "$wt" "$row"
done
[ "$(grep -c 'unlexable' "$gb_log")" = 8 ] && ok "guard-bash: unlexable: every one logged" \
  || bad "guard-bash: unlexable: every one logged ($(grep -c 'unlexable' "$gb_log") of 8)"
: > "$gb_log"
gb 0 "unlexable: a multi-line command stays one log line" "$wt" $'echo "one\ntwo'
[ "$(wc -l < "$gb_log" | tr -d ' ')" = 1 ] && ok "guard-bash: unlexable: one line per entry" \
  || bad "guard-bash: unlexable: one line per entry"
gb 2 "unlexable: what came before the bad part is still checked" "$wt" 'cat .env; echo "unterminated'
mv "$fx/.agent/state" "$fx/.agent/state.away"
gb 0 "unlexable: an unwritable log doesn't get in the way" "$wt" 'echo "unterminated'
mv "$fx/.agent/state.away" "$fx/.agent/state"

# --- Contract scope and maintainer mode come with the shared policy ---
cp "$wt/.agent/contracts/demo.md" "$aux/demo.md.keep"
echo demo > "$wt/.agent/state/active-task"
printf '# Contract: demo\n## Target files\n- src/app.py\n' > "$wt/.agent/contracts/demo.md"
gb 0 "contract: target"        "$wt" 'echo x > src/app.py'
gb 2 "contract: outside"       "$wt" 'echo x > src/other.py' "outside the contract"
gb 0 "contract: sed's BSD suffix is no target" "$wt" "sed -i .bak 's/a/b/' src/app.py"
gb 2 "contract: sed's dotted file is a target"  "$wt" "sed -e 's/a/b/' -i .other"  "outside the contract"
gb 0 "contract: agent dir"     "$wt" 'echo x >> .agent/lessons.md'
gb 0 "contract: read outside"  "$wt" 'cat src/other.py'
rm -f "$wt/.agent/state/active-task"
cp "$aux/demo.md.keep" "$wt/.agent/contracts/demo.md"
gb 2 "danger zone without contract" "$wt" 'echo x > src/billing/pay.py' "danger zone"
gb 0 "maintainer: harness"     "$wt" 'echo x > .claude/hooks/a.sh' "" maint
gb 2 "maintainer: secrets"     "$wt" 'echo x > .env'               "protected path" maint
gb 2 "maintainer: reads"       "$wt" 'cat .env'                    "protected path" maint
gb 2 "maintainer: git push"    "$wt" 'git push'                    "denied" maint

# The reasons are the ones the write guard gives
gb 2 "message: secrets"        "$wt" 'echo x > .env'  "protected path (secrets)"
gb 2 "message: main"           "$fx" 'echo x > src/app.py' "you are on main"
gb 2 "message: harness"        "$wt" 'echo x > CLAUDE.md'  "harness infrastructure"
gb 2 "message: read"           "$wt" 'cat .env'       "Don't read it"
gb 2 "message: git"            "$wt" 'git -C . push'  "! prefix"

# git missing: a write can't be checked, everything else still works
gbreader=jq; command -v jq >/dev/null 2>&1 || gbreader=python3
gbnogit="$(tool_dir gb-nogit cat dirname date "$gbreader")"
gb_raw 2 "git missing: write blocked"    "$gbnogit" "$BASH" "$(bash_in "$wt" 'echo x > src/app.py')" "git is missing"
gb_raw 0 "git missing: /dev/null passes" "$gbnogit" "$BASH" "$(bash_in "$wt" 'echo x 2>/dev/null')"
gb_raw 0 "git missing: plain read passes" "$gbnogit" "$BASH" "$(bash_in "$wt" 'cat src/app.py')"
gb_raw 2 "git missing: secret read blocked" "$gbnogit" "$BASH" "$(bash_in "$wt" 'cat .env')" "protected path"

# Either JSON reader will do
if command -v python3 >/dev/null 2>&1; then
  gbpy="$(tool_dir gb-py cat dirname date git python3)"
  gb_raw 2 "python fallback: blocked" "$gbpy" "$BASH" "$(bash_in "$wt" 'echo "x" > .env')" "protected path"
  gb_raw 0 "python fallback: allowed" "$gbpy" "$BASH" "$(bash_in "$wt" $'cat <<\'EOF\'\ngit push\nEOF')"
  gb_raw 2 "python fallback: non-ascii" "$gbpy" "$BASH" "$(bash_in "$wt" 'echo "вітаю ✓"; cat .env')" "protected path"
else
  echo "SKIP  guard-bash: python fallback (python3 not installed)"
fi
if command -v jq >/dev/null 2>&1; then
  gb 2 "non-ascii: bytes survive" "$wt" 'echo "вітаю ✓" > .env' "protected path"
  gb 0 "non-ascii: in a quote"    "$wt" "echo 'вітаю > .env ✓'"
fi

# --- Criterion 8: the lexer is pure bash on 3.2 ---
# A stub reader stands in for JSON parsing, so nothing but bash and git can have done the lexing.
lexdir="$(tool_dir gb-lex cat dirname git)"
cat > "$lexdir/jq" <<STUB
#!/bin/sh
case "\$2" in
  *command*) cat "$aux/lex-cmd" ;;
  *) echo "$wt" ;;
esac
STUB
chmod +x "$lexdir/jq"
bash32=""; [ -x /bin/bash ] && bash32=/bin/bash
for sh in "$BASH" $bash32; do
  printf '%s' 'echo "a > .env"; cat <<EOF
git push
EOF
echo $(echo "$(true)") `true` | tee /dev/null' > "$aux/lex-cmd"
  gb_raw 0 "pure bash ($sh): allowed" "$lexdir" "$sh" '{}'
  printf '%s' 'echo "a"; true && (echo "$(cd src; git -C . push)")' > "$aux/lex-cmd"
  gb_raw 2 "pure bash ($sh): blocked" "$lexdir" "$sh" '{}' "denied"
done

# --- Must finish: a timeout passes the command unchecked and unlogged, so a hang is a hole ---
# A background run with a kill: stock macOS has no `timeout`, and a regression must fail its case,
# not hang the self-test. The limit is half the 30 seconds in settings.json.
gb_limit=15
gb_finish() { # gb_finish <expected-exit> <name> <file holding the hook input> [limit]
  local want="$1" name="$2" file="$3" limit="${4:-$gb_limit}" pid got end=$((SECONDS + ${4:-$gb_limit}))
  ( unset HARNESS_MAINTAINER HARNESS_ROLE
    exec "$BASH" "$gb_hook" < "$file" >/dev/null 2>&1 ) &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$SECONDS" -ge "$end" ]; then
      kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
      bad "guard-bash: must-finish: $name (still running after ${limit}s)"; return
    fi
    sleep 0.02
  done
  wait "$pid"; got=$?
  if [ "$got" = "$want" ]; then ok "guard-bash: must-finish: $name"
  else bad "guard-bash: must-finish: $name (want exit $want, got $got)"; fi
}
gb_file() { printf '%s' "$1" > "$gb_fin"; echo "$gb_fin"; }

# These run side by side (see par_begin), each in a subshell with a private copy of the hook, so its
# log and input file are its own. A case that reads the log can't see another case's lines.
mf_setup() {
  mkdir -p "$PD/.claude" "$PD/.agent/state" && cp -R "$fx/.claude/hooks" "$PD/.claude/hooks" || return 1
  gb_hook="$PD/.claude/hooks/guard-bash.sh"; gb_log="$PD/.agent/state/guard-bash.log"; gb_fin="$PD/finish.json"
}

# Malformed: every way to stop in the middle of something. %BS% = a backslash at the very end.
par_begin
{ mf_setup
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    cmd="$(gb_expand "$row")"; cmd="${cmd//%BS%/\\}"
    gb_finish 0 "malformed: $row" "$(gb_file "$(bash_in "$wt" "$cmd")")"
  done
} > "$PF" <<'ROWS' &
%BS%
echo %BS%
echo "%BS%
echo 'x%BS%
echo $'%BS%
echo `%BS%
echo "$(%BS%
"
'
`
$
$(
$((
${
$'
$"
echo "$
echo "${
echo "$(
echo "`
echo "$(echo "
<
>
<<
<<<
<<-
<&
>&
&>
&
|
(
)
((
))
#
# comment with no newline
cat <<
cat <<EOF
cat <<EOF%NL%
cat <<EOF%NL%body
cat <<EOF%NL%body%NL%
cat <<-EOF
cat <<-EOF%NL%%TAB%body
cat <<'EOF
cat <<"EOF
cat <<A <<B%NL%a%NL%A
echo $(cat <<EOF%NL%body
echo "$(cat <<EOF%NL%body%NL%EOF
cd
git
git -C
git -c
git add
env
env -u
timeout
timeout 5
xargs -I
sed -i
sed -e
perl -e
cp
mv a
ln
dd
bash -c
eval
ROWS
par_end $!

# rep <text> <doublings> : sets REP. Doubling, because ${x//} and per-item loops are far too slow.
rep() { REP="$1"; local i=0; while [ "$i" -lt "$2" ]; do REP="$REP$REP"; i=$((i + 1)); done; }
# Written as JSON by hand for the same reason. <text> needs no escaping, or arrives escaped.
gb_big() { printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"%s"}}' "$wt" "$1" > "$gb_fin"; }

# Each one hung the hook, or came close, before the limits went in.
over() { # over <name> : the last input ran out of budget. It passes and says so in the log.
  : > "$gb_log"
  gb_finish 0 "$1" "$gb_fin"
  if grep -q 'unlexable: over budget' "$gb_log"; then ok "guard-bash: must-finish: $1: logged"
  else bad "guard-bash: must-finish: $1: logged"; fi
}
# mf_case <cmd...> : one case in the background, its own subshell and private hook copy.
mf_case() { par_begin; ( mf_setup && "$@" ) > "$PF" & par_end $!; }

# Forks are where the time goes when the lexer is fine. Each check here costs a second, so only
# the clock can stop it. Started first, because it outlasts everything else here. Slow on purpose: once per run, not again inside the git env leak replay.
if [ -n "${HARNESS_SELFTEST_NESTED:-}" ]; then
  echo "SKIP  guard-bash: must-finish: slow git (already inside the replay)"
else
  slowdir="$(tool_dir gb-slow cat dirname date "$gbreader")"
  printf '#!/bin/sh\nsleep 1\nexit 128\n' > "$slowdir/git"; chmod +x "$slowdir/git"
  mf_slow() {
    rep 'cat a; ' 8
    bash_in "$wt" "$REP" > "$gb_fin"
    : > "$gb_log"
    ( PATH="$slowdir:$PATH"; gb_finish 0 "slow git stops at the deadline" "$gb_fin" 25 ) | sed 's/^/ /' > "$PD/slow.out"
    if grep -q PASS "$PD/slow.out"; then ok "guard-bash: must-finish: slow git stops at the deadline"
    else bad "guard-bash: must-finish: slow git stops at the deadline ($(cat "$PD/slow.out"))"; fi
    grep -q 'unlexable: over budget' "$gb_log" && ok "guard-bash: must-finish: slow git logged" \
      || bad "guard-bash: must-finish: slow git logged"
  }
  mf_case mf_slow
fi

mf_over() { rep "$1" "$2"; gb_big "${4:-}$REP${5:-}"; over "$3"; }
mf_case mf_over "''" 19 "1MB of empty quotes"
mf_case mf_over "x " 19 "1MB of short words"
mf_case mf_over 'a$' 19 "1MB of specials in double quotes" '\"' '\"'
mf_case mf_over '`x` ' 17 "512KB of backticks"
mf_case mf_over '# x\n' 18 "1MB of comment lines"
mf_case mf_over '( ' 15 "32768 open parens"
mf_parens() { rep '(' 15; gb_big "$REP"; gb_finish 0 "32768 parens in a row, read as arithmetic" "$gb_fin"; }
mf_case mf_parens
mf_case mf_over '$(' 15 "32768 open substitutions"
mf_case mf_over 'echo x > a; ' 12 "4096 targets"
mf_case mf_over 'x' 22 "4MB word"
mf_case mf_over 'a' 22 "4MB flag cluster" "cat -"
mf_case mf_over 'x\n' 21 "tab heredoc, 2M lines" 'cat <<-E\n' '\tE'

mf_logs() {
  : > "$gb_log"
  rep 'x\n' 19;          gb_big "echo \\\"$REP"; gb_finish 0 "1MB unterminated, must log a short line" "$gb_fin"
  [ "$(wc -c < "$gb_log" | tr -d ' ')" -lt 400 ] && ok "guard-bash: must-finish: log line stays short" \
    || bad "guard-bash: must-finish: log line stays short"
  rep 'cat $x; ' 15;     gb_big "$REP"; : > "$gb_log"; gb_finish 0 "32768 unresolved targets" "$gb_fin"
  [ "$(wc -l < "$gb_log" | tr -d ' ')" -le 51 ] && ok "guard-bash: must-finish: log lines are bounded" \
    || bad "guard-bash: must-finish: log lines are bounded ($(wc -l < "$gb_log"))"
  rep '../' 12;          gb_big "cat ${REP}x"; : > "$gb_log"; gb_finish 0 "path past PATH_MAX" "$gb_fin"
  grep -q 'target too long' "$gb_log" && ok "guard-bash: must-finish: long path logged" \
    || bad "guard-bash: must-finish: long path logged"
  rep 'y' 15;            gb_big "$REP a"; : > "$gb_log"; gb_finish 0 "32KB command name" "$gb_fin"
  grep -q 'word too long' "$gb_log" && ok "guard-bash: must-finish: long word logged" \
    || bad "guard-bash: must-finish: long word logged"
}
mf_case mf_logs

# A heredoc is the one big command that's normal: the whole of it has to be read, not given up on.
mf_heredoc() {
  local line='print(\"some line of generated code, long enough to look like a real one\")\n'
  rep "$line" 12
  gb_big "cat > src/big.py <<'EOF'\n${REP}EOF"
  : > "$gb_log"; gb_finish 0 "4096-line heredoc" "$gb_fin"
  [ ! -s "$gb_log" ] && ok "guard-bash: must-finish: 4096-line heredoc read to the end" \
    || bad "guard-bash: must-finish: 4096-line heredoc read to the end ($(cut -f2 "$gb_log"))"
  gb_big "cat > src/big.py <<'EOF'\n${REP}EOF\ngit push"
  gb_finish 2 "command after a big heredoc is seen" "$gb_fin"
  gb_big "cat > .env <<'EOF'\n${REP}EOF"
  gb_finish 2 "target of a big heredoc is seen" "$gb_fin"
}
mf_case mf_heredoc
mf_heredoc4() {
  rep 'x\n' 21
  gb_big "cat <<'EOF'\n${REP}EOF\ngit push"
  gb_finish 2 "command after a 4MB heredoc of short lines" "$gb_fin"
}
mf_case mf_heredoc4
# The closing line can fall anywhere against the search window, so walk it across one boundary.
mf_window() {
  local pad body
  for pad in 8180 8181 8182 8183 8184 8185 8186 8187 8188 8189 8190 8191 8192 8193; do
    rep 'x' 13; body="${REP:0:$pad}"
    gb_big "cat <<'EOF'\n$body\nEOF\ngit push"
    gb_finish 2 "closing line at offset $pad" "$gb_fin"
  done
  # ...and the words and quoted strings that run past one
  rep 'x' 13
  gb_finish 2 "quote past the window" "$(gb_file "$(bash_in "$wt" "echo '${REP}y z'; git push")")"
  gb_finish 2 "double quote past the window" "$(gb_file "$(bash_in "$wt" "echo \"${REP}y z\"; git push")")"
  gb_finish 0 "comment past the window stays a comment" "$(gb_file "$(bash_in "$wt" "# ${REP}; git push")")"
  gb_finish 2 "command after a comment past the window" "$(gb_file "$(bash_in "$wt" "# ${REP}y z"$'\n'"git push")")"
}
mf_case mf_window
# One search can't be stopped by a budget, so one long string is the test of the window itself.
mf_str1() { rep 'x' 22; gb_big "echo '$REP'"; gb_finish 0 "4MB single-quoted string" "$gb_fin"; }
mf_str2() { rep 'x' 22; gb_big "echo \\\"$REP\\\""; gb_finish 0 "4MB double-quoted string" "$gb_fin"; }
mf_case mf_str1
mf_case mf_str2

par_flush

# A job that dies must count as a failure. par_dead <body…> runs one job in a subshell with its own
# counters and scratch dir (nothing else is in flight here), and prints "<pass> <fail>".
par_dead() {
  ( aux="$aux/par-dead"; mkdir -p "$aux"; pass=0; fail=0
    PAR_SEQ=0; PAR_HEAD=0; PAR_TAIL=0; PAR_PIDS=(); PAR_FILES=()
    par_begin; "$@" > "$PF" & par_end $!
    par_flush > /dev/null; echo "$pass $fail" )
}
pd_killed() { echo "PASS  half done"; bash -c 'kill -9 $$'; }
pd_exit3()  { echo "PASS  looked fine"; exit 3; }
pd_silent() { :; }
pd_good()   { echo "PASS  fine"; }
[ "$(par_dead pd_killed)" = "1 1" ] && ok "par: dead job: killed job counts as FAIL" || bad "par: dead job: killed job counts as FAIL (got '$(par_dead pd_killed)')"
[ "$(par_dead pd_exit3)" = "1 1" ] && ok "par: dead job: non-zero exit counts as FAIL" || bad "par: dead job: non-zero exit counts as FAIL (got '$(par_dead pd_exit3)')"
[ "$(par_dead pd_silent)" = "0 1" ] && ok "par: dead job: silent job counts as FAIL" || bad "par: dead job: silent job counts as FAIL (got '$(par_dead pd_silent)')"
[ "$(par_dead pd_good)" = "1 0" ] && ok "par: dead job: healthy job is not a FAIL" || bad "par: dead job: healthy job is not a FAIL (got '$(par_dead pd_good)')"

# Wired into settings.json, with a timeout of its own
hook_setting() { # hook_setting <field>: matcher or timeout of the guard-bash entry
  if command -v jq >/dev/null 2>&1; then
    case "$1" in
      matcher) jq -r '.hooks.PreToolUse[] | select(any(.hooks[]; .command | contains("guard-bash.sh"))) | .matcher' "$ROOT/.claude/settings.json" ;;
      timeout) jq -r '.hooks.PreToolUse[].hooks[] | select(.command | contains("guard-bash.sh")) | .timeout' "$ROOT/.claude/settings.json" ;;
    esac
  else
    python3 -c 'import json,sys
for e in json.load(open(sys.argv[1]))["hooks"]["PreToolUse"]:
    for h in e["hooks"]:
        if "guard-bash.sh" in h["command"]:
            print(e.get("matcher") if sys.argv[2] == "matcher" else h.get("timeout"))' "$ROOT/.claude/settings.json" "$1"
  fi
}
[ "$(hook_setting matcher)" = Bash ] && ok "guard-bash: settings: matches Bash" || bad "guard-bash: settings: matches Bash"
[ "$(hook_setting timeout)" = 30 ] && ok "guard-bash: settings: timeout 30" || bad "guard-bash: settings: timeout 30 (got '$(hook_setting timeout)')"
