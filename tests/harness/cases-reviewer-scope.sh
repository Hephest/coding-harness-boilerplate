# Sourced by run.sh: reviewer scope cases (contract v02-reviewer-scope).
# Uses run.sh's fixture and cases-guard-bash.sh's json_str, which sorts before this file.

rv_hook="$fx/.claude/hooks/guard-bash.sh"

# rv <expected-exit> <name> <command> [agent_type] [HARNESS_ROLE] [text stderr must contain]
# Rows run side by side, see par_begin in cases-guard-bash.sh; the lines come out in order.
rv() { par_begin; rv_row "$@" > "$PF" & par_end $!; }
rv_row() {
  local want="$1" name="$2" cmd="$3" agent="${4:-}" role="${5:-}" needle="${6:-}" extra="" err got
  [ -n "$agent" ] && extra=",\"agent_type\":\"$agent\""
  err="$( unset HARNESS_MAINTAINER HARNESS_ROLE
          [ -n "$role" ] && export HARNESS_ROLE="$role"
          printf '{"tool_name":"Bash","cwd":%s%s,"tool_input":{"command":%s}}' \
            "$(json_str "$wt")" "$extra" "$(json_str "$cmd")" | "$BASH" "$rv_hook" 2>&1 >/dev/null )"
  got=$?
  if [ "$got" != "$want" ]; then bad "reviewer: $name (want exit $want, got $got: $err)"
  elif [ -n "$needle" ] && [[ "$err" != *"$needle"* ]]; then bad "reviewer: $name (stderr lacks '$needle': $err)"
  else ok "reviewer: $name"; fi
}

# Allowed, by agent_type and by HARNESS_ROLE alike
while IFS= read -r c; do
  [ -n "$c" ] || continue
  rv 0 "allowed (agent_type): $c" "$c" reviewer
  rv 0 "allowed (HARNESS_ROLE): $c" "$c" "" reviewer
done <<'ROWS'
scripts/verify.sh
./scripts/verify.sh
scripts/verify.sh --fast src/app.py
git diff
git diff main...HEAD
git diff --stat -- src
git log --oneline -n 5
git show HEAD:src/app.py
git status --short
git diff main...HEAD | head -50
git log | grep fix | wc -l
git diff main...HEAD 2>&1 | tail -n 20
scripts/verify.sh 2>&1 | tail -5
git diff > /dev/null
git status && git log -1
ROWS

# Blocked
while IFS= read -r c; do
  [ -n "$c" ] || continue
  rv 2 "blocked (agent_type): $c" "$c" reviewer
  rv 2 "blocked (HARNESS_ROLE): $c" "$c" "" reviewer
done <<'ROWS'
ls
cat src/app.py
echo hi > out.txt
git diff > out.patch
git diff >> out.patch
git status | tee x
git diff --output=x.patch
git diff --out x.patch
git diff --output-indicator-new=x --output=y
git diff --ext-diff
git diff --ext
git show --textconv HEAD
git diff --no-index /dev/null .env
git -c core.pager=sh log
git -C /tmp log
git --git-dir=/tmp/x log
git diff --help
git commit -m x
git branch
git checkout main
git push
git log; touch x
git log && rm x
git log || sh -c 'id'
sh -c 'git log'
bash scripts/verify.sh
env git log
GIT_EXTERNAL_DIFF=/bin/true git diff
nice git log
git diff $(echo --output=x)
git diff `echo x`
git diff $X
git log | sh
git log | xargs rm
git log | head -n 5 > x
git log | head .env
python3 -c 'print(1)'
git log "unterminated
git log (
(git log
scripts/verify.sh <<EOF
git log <<< hi
( git log ) > x
if true; then git log; fi
ROWS

# Past the lexer budget, a reviewer command blocks; the general guard passes it
rv 2 "fail closed: unterminated quote"       "git log 'oops" reviewer "" "can't be fully read"
rv 0 "others: unterminated quote passes"     "git log 'oops"
deep="$(printf '$(%.0s' $(seq 1 80))true$(printf ')%.0s' $(seq 1 80))"
rv 2 "fail closed: nested past the limit"    "git log $deep" reviewer "" "can't be fully read"
rv 0 "others: nested past the limit passes"  "git log $deep"

# Either signal is enough, and a mismatch takes the stricter reading
rv 2 "mixed: agent_type other, role reviewer" "ls" other reviewer
rv 2 "mixed: agent_type reviewer, role other" "ls" reviewer other
rv 2 "agent_type case is ignored"             "ls" Reviewer
rv 2 "role case is ignored"                   "ls" "" REVIEWER

# Everyone else is unaffected
rv 0 "others: main session runs ls"           "ls"
rv 0 "others: redirect"                       "echo hi > $wt/note.txt"
rv 0 "others: other agent"                    "git -C . status" test-runner
rv 0 "others: other role"                     "ls" "" builder
rv 2 "others: still guarded (git push)"       "git push" test-runner

# The reviewer still can't read secrets through the allowed tools
rv 2 "reviewer: grep of .env blocks"          "grep KEY .env" reviewer
par_flush
