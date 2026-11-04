# Sourced by run.sh: contract approval (contract v02-contract-approval).
# Sorts before the guard-bash cases, so it brings its own hook call. Cleans up after itself, with
# one exception on purpose: the block at the end, which sets the stage for the case files after it.

approve_sh="$ROOT/scripts/contract-approve.sh"
store="$fx/.git/harness/approved"

# ca_bash <expected-exit> <name> <cwd> <command> [text stderr must contain] [maintainer]
# The commands here hold no quotes or backslashes, so printf can write the JSON.
ca_bash() {
  local want="$1" name="$2" cwd="$3" cmd="$4" needle="${5:-}" maint="${6:-}" err got
  err="$( unset HARNESS_MAINTAINER HARNESS_ROLE
          [ -n "$maint" ] && export HARNESS_MAINTAINER=1
          printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"%s"}}' "$cwd" "$cmd" \
            | "$BASH" "$fx/.claude/hooks/guard-bash.sh" 2>&1 >/dev/null )"
  got=$?
  if [ "$got" != "$want" ]; then bad "guard-bash: $name (want exit $want, got $got: $err)"
  elif [ -n "$needle" ] && [[ "$err" != *"$needle"* ]]; then bad "guard-bash: $name (stderr lacks '$needle': $err)"
  else ok "guard-bash: $name"; fi
}

# ca_write <expected-exit> <name> <path> [text stderr must contain]
ca_write() { guard_raw "$1" "$2" "$PATH" "$(input "$3")" "${4:-}"; }

ca_approve() { ( cd "$1" && "$approve_sh" "$2" ) >/dev/null 2>&1; }

# ca_run <expected-exit> <name> <dir> <id> [text the output must contain] : the script, as a human runs it.
ca_run() {
  local want="$1" name="$2" dir="$3" needle="${5:-}" out got
  shift 3
  out="$( cd "$dir" && "$approve_sh" "${1:-}" 2>&1 )"
  got=$?
  if [ "$got" != "$want" ]; then bad "guard: approval: $name (want exit $want, got $got: $out)"
  elif [ -n "$needle" ] && [[ "$out" != *"$needle"* ]]; then bad "guard: approval: $name (output lacks '$needle': $out)"
  else ok "guard: approval: $name"; fi
}

ca_contract() { # ca_contract <dir> <id> : a filled-in contract
  mkdir -p "$1/.agent/contracts" "$1/.agent/state"
  printf '# Contract: %s\n\n## Target files\n- src/app.py\n- src/extra.py\n\n## Acceptance criteria\n1. it works\n' "$2" \
    > "$1/.agent/contracts/$2.md"
}

g "$fx" worktree add -q -b task/appr "$fx/.worktrees/appr" HEAD
ap="$fx/.worktrees/appr"
ac="$ap/.agent/contracts/appr.md"
state="$ap/.agent/state/active-task"

# --- Criterion 1: recorded under the git common dir, seen from every worktree ---
ca_contract "$fx" early
ca_run 0 "common dir: approves from the main checkout" "$fx" early
[ -f "$store/early.sha256" ] && ok "guard: approval: common dir: stored under .git" \
  || bad "guard: approval: common dir: stored under .git"
g "$fx" worktree add -q -b task/early "$fx/.worktrees/early" HEAD
ca_write 2 "approval: common dir: contract not copied in yet" "$fx/.worktrees/early/src/app.py"
ca_contract "$fx/.worktrees/early" early
ca_write 0 "approval: common dir: main's approval counts in the worktree" "$fx/.worktrees/early/src/app.py"
ca_contract "$ap" appr
ca_run 0 "common dir: approves from a worktree" "$ap" appr
[ -f "$store/appr.sha256" ] && ok "guard: approval: common dir: a worktree stores in the same place" \
  || bad "guard: approval: common dir: a worktree stores in the same place"
[ -z "$(find "$fx/.git/worktrees" -path '*harness*')" ] && ok "guard: approval: common dir: nothing per worktree" \
  || bad "guard: approval: common dir: nothing per worktree"
mkdir -p "$ap/src"
ca_run 0 "common dir: approves from a subdirectory" "$ap/src" appr
ca_write 0 "approval: common dir: approved contract, write allowed" "$ap/src/app.py"
rm -f "$store/appr.sha256"

# --- Criterion 2: the id comes from the branch, not from a file the agent can change ---
echo appr > "$state"
ca_write 2 "approval: active-task names the task" "$ap/src/app.py" "isn't approved"
: > "$state"
ca_write 2 "approval: blank active-task" "$ap/src/app.py" "isn't approved"
printf ' \n' > "$state"
ca_write 2 "approval: blank active-task, whitespace" "$ap/src/app.py" "isn't approved"
rm -f "$state"
ca_write 2 "approval: blank active-task, deleted" "$ap/src/app.py" "isn't approved"
echo nothing > "$state"
ca_write 2 "approval: blank active-task, another name" "$ap/src/other.py" "isn't approved"
rm -f "$state"

# Any other branch has no id of its own, so active-task names the task there.
g "$fx" worktree add -q -b feature/ca "$fx/.worktrees/feature" HEAD
fe="$fx/.worktrees/feature"
ca_contract "$fe" feat
ca_write 0 "approval: other branch, no active task" "$fe/src/app.py"
echo feat > "$fe/.agent/state/active-task"
ca_write 2 "approval: other branch, active task unapproved" "$fe/src/app.py" "isn't approved"
ca_approve "$fx/.worktrees/early" early
ca_bash  2 "approval: one command, two checkouts: the second is checked too" "$fx/.worktrees/early" \
  "echo x > src/app.py; echo x > $fe/src/app.py" "isn't approved"
ca_approve "$fe" feat
ca_write 0 "approval: other branch, active task approved" "$fe/src/app.py"
rm -f "$fe/.agent/state/active-task" "$store/feat.sha256"

# --- Criterion 3: unapproved or edited blocks, a fresh approval unblocks ---
ca_write 2 "approval: edited contract: never approved" "$ap/src/app.py" "isn't approved"
ca_bash  2 "approval: edited contract: shell write too" "$ap" 'echo x > src/app.py' "isn't approved"
ca_write 2 "approval: message gives the command" "$ap/src/app.py" "! scripts/contract-approve.sh appr"
ca_write 2 "approval: message gives the terminal way" "$ap/src/app.py" "cd $ap && scripts/contract-approve.sh appr"
ca_approve "$ap" appr
ca_write 0 "approval: edited contract: approved" "$ap/src/app.py"
ca_bash  0 "approval: edited contract: approved, shell" "$ap" 'echo x > src/app.py'
printf '\n' >> "$ac"
ca_write 2 "approval: edited contract: one byte" "$ap/src/app.py" "changed since"
ca_bash  2 "approval: edited contract: one byte, shell" "$ap" 'echo x > src/app.py' "changed since"
ca_write 2 "approval: edited contract: message gives the command" "$ap/src/app.py" "! scripts/contract-approve.sh appr"
ca_approve "$ap" appr
ca_write 0 "approval: edited contract: approved again" "$ap/src/app.py"
: > "$store/appr.sha256"
ca_write 2 "approval: edited contract: empty record" "$ap/src/app.py" "changed since"
ca_approve "$ap" appr
ca_bash  2 "approval: harness rules still come first" "$ap" 'echo x > .claude/settings.json' "harness infrastructure"
echo appr > "$state"
ca_write 2 "approval: contract scope still applies" "$ap/src/other.py" "outside the contract"
ca_write 0 "approval: contract scope still allows" "$ap/src/extra.py"
rm -f "$state"
printf '\n' >> "$ac"
ca_bash  2 "approval: maintainer mode doesn't skip it" "$ap" 'echo x > src/app.py' "changed since" maint
ca_approve "$ap" appr

# --- Criterion 4: deleting the contract doesn't lift enforcement ---
cp "$ac" "$aux/appr.md.keep"
rm -f "$ac"
ca_write 2 "approval: deleted contract" "$ap/src/app.py" "was approved"
ca_bash  2 "approval: deleted contract, shell" "$ap" 'echo x > src/app.py' "was approved"
cp "$aux/appr.md.keep" "$ac"
ca_write 0 "approval: deleted contract: restored as approved" "$ap/src/app.py"

# --- Criterion 5: no contract, no approval, no active task: as before ---
ca_write 0 "approval: nothing to check" "$st/src/new.py"
ca_bash  0 "approval: nothing to check, shell" "$st" 'echo x > src/new.py'

# --- Criterion 6: the agent can't approve ---
for rule in 'Bash(scripts/contract-approve.sh:*)' 'Bash(./scripts/contract-approve.sh:*)'; do
  if grep -qxF "$rule" <<< "$denied"; then ok "settings: approval: denies $rule"; else bad "settings: approval: denies $rule"; fi
done
guard 2 "approval: agent blocked: script is a harness file"       "$ap/scripts/contract-approve.sh"
guard 2 "approval: agent blocked: store through the write tool"   "$store/appr.sha256"
guard 2 "approval: agent blocked: store in maintainer mode"       "$store/appr.sha256" maint
ca_bash 2 "approval: agent blocked: script edited from the shell" "$ap" 'echo x > scripts/contract-approve.sh' "harness infrastructure"
ca_bash 2 "approval: agent blocked: script moved" "$ap" 'mv scripts/contract-approve.sh x' "harness infrastructure"
ca_bash 2 "approval: agent blocked: store from the shell"   "$ap" "echo x > $store/appr.sha256" "git internals"
ca_bash 2 "approval: agent blocked: store removed"          "$ap" "rm -f $store/appr.sha256" "git internals"
ca_bash 2 "approval: agent blocked: store directory moved"  "$ap" "mv $fx/.git/harness x" "git internals"
while IFS= read -r row; do
  [ -n "$row" ] || continue
  ca_bash 2 "approval: agent blocked: $row" "$ap" "$row" "only the user"
done <<ROWS
scripts/contract-approve.sh appr
./scripts/contract-approve.sh appr
$ap/scripts/contract-approve.sh appr
bash scripts/contract-approve.sh appr
sh scripts/contract-approve.sh appr
bash -x scripts/contract-approve.sh appr
source scripts/contract-approve.sh appr
. scripts/contract-approve.sh appr
env scripts/contract-approve.sh appr
command scripts/contract-approve.sh appr
nohup scripts/contract-approve.sh appr
echo appr | xargs scripts/contract-approve.sh
true && scripts/contract-approve.sh appr
bash -c 'scripts/contract-approve.sh appr'
eval scripts/contract-approve.sh appr
echo \$(scripts/contract-approve.sh appr)
cd scripts && ./contract-approve.sh appr
ROWS
ca_bash 2 "approval: agent blocked: maintainer mode too" "$ap" 'scripts/contract-approve.sh appr' "only the user" maint
ca_bash 0 "approval: agent can read the script" "$ap" 'cat scripts/contract-approve.sh'
ca_bash 0 "approval: other scripts still run"  "$ap" 'bash scripts/x.sh'

# --- Criterion 7: a blocked agent can still fix its contract ---
printf '\n' >> "$ac"
ca_write 2 "approval: contract stays writable: blocked elsewhere" "$ap/src/app.py" "changed since"
ca_write 0 "approval: contract stays writable: the contract"     "$ac"
ca_bash  0 "approval: contract stays writable: from the shell"   "$ap" 'echo x >> .agent/contracts/appr.md'
ca_write 0 "approval: contract stays writable: receipts and state" "$ap/.agent/receipts/appr.md"
ca_approve "$ap" appr

# sha256: either tool will do, and with neither the guard and the script both fail closed.
reader=jq; command -v jq >/dev/null 2>&1 || reader=python3
nosha="$(tool_dir ca-nosha cat dirname git "$reader")"
guard_raw 2 "approval: no hash tool: blocked" "$nosha" "$(input "$ap/src/app.py")" "sha256"
guard_raw 0 "approval: no hash tool: .agent stays open" "$nosha" "$(input "$ac")"
guard_raw 0 "approval: no hash tool: no contract, nothing to hash" "$nosha" "$(input "$st/src/new.py")"
for sha in shasum sha256sum; do
  if command -v "$sha" >/dev/null 2>&1; then
    guard_raw 0 "approval: $sha alone will do" "$(tool_dir "ca-$sha" cat dirname git "$reader" "$sha")" "$(input "$ap/src/app.py")"
  else
    echo "SKIP  guard: approval: $sha alone will do (not installed)"
  fi
done
scriptdir="$(tool_dir ca-script cat dirname git sed grep awk mkdir)"
cp "$store/appr.sha256" "$aux/appr.sha.keep"
printf '\n' >> "$ac"
out="$( cd "$ap" && PATH="$scriptdir" "$BASH" "$approve_sh" appr 2>&1 )"; code=$?
if [ "$code" = 1 ] && [[ "$out" == *"shasum"* ]] && cmp -s "$store/appr.sha256" "$aux/appr.sha.keep"; then
  ok "guard: approval: no hash tool: the script refuses"
else
  bad "guard: approval: no hash tool: the script refuses (exit $code: $out)"
fi

# --- The script: shows what it approves, and refuses what can't be approved ---
ca_contract "$ap" appr
ca_run 0 "script: prints the target files" "$ap" appr "src/extra.py"
ca_run 0 "script: prints the criteria"     "$ap" appr "it works"
ca_run 1 "script: no such contract"        "$ap" ghost "no contract"
ca_run 1 "script: id can't leave the store" "$ap" "../../x" "not a task id"
ca_run 1 "script: id can't be a flag"      "$ap" "-x"     "not a task id"
[ ! -e "$store/ghost.sha256" ] && ok "guard: approval: script: nothing recorded for a refusal" \
  || bad "guard: approval: script: nothing recorded for a refusal"
out="$( cd "$fx" && "$approve_sh" 2>&1 )"; code=$?
[ "$code" = 2 ] && ok "guard: approval: script: needs an id" || bad "guard: approval: script: needs an id (exit $code: $out)"
out="$( cd "$fx" && "$approve_sh" a b 2>&1 )"; code=$?
[ "$code" = 2 ] && ok "guard: approval: script: one id only" || bad "guard: approval: script: one id only (exit $code: $out)"

refused() { # refused <name> <text the output must contain> : .agent/contracts/ref.md is on disk
  ca_run 1 "script: refuses: $1" "$ap" ref "$2"
  if [ -e "$store/ref.sha256" ]; then bad "guard: approval: script: refuses: $1 (recorded)"
  else ok "guard: approval: script: refuses: $1 (nothing recorded)"; fi
}
rc="$ap/.agent/contracts/ref.md"
cp "$ROOT/.agent/contracts/TEMPLATE.md" "$rc"
refused "the template as it is" "placeholders"
for ph in '<task-id>' '<what changes and why>' '<observable behaviour>' '<things the agent must not touch or "improve" while it is there>' \
          '<schema rules, API contracts, gotchas from .agent/lessons.md>' 'covered by `<test name>`'; do
  ca_contract "$ap" ref; printf '%s\n' "$ph" >> "$rc"
  refused "placeholder $ph" "placeholders"
done
for ph in '- src/<path>/<file>' '- tests/<path>/test_<file>' '- src/<file>' '- src/<path>/app.py'; do
  printf '# Contract: ref\n## Target files\n%s\n' "$ph" > "$rc"
  refused "placeholder target $ph" "placeholders"
done
ca_contract "$ap" ref; printf 'Quotes `task/<id>` and `<file>` in code, and <!-- <path> --> in a comment.\n' >> "$rc"
ca_run 0 "script: a quoted <id> is no placeholder" "$ap" ref
rm -f "$store/ref.sha256"

printf '# Contract: ref\n## Target files\n- a\n- b\n- c\n- d\n- e\n- f\n## Acceptance criteria\n1. x\n' > "$rc"
refused "six target files" "limit is 5"
printf '# Contract: ref\n## Target files\n- a\n- b\n- c\n- d\n- e\n## Acceptance criteria\n- x\n- y\n- z\n- w\n' > "$rc"
ca_run 0 "script: five target files are fine" "$ap" ref
rm -f "$store/ref.sha256" "$rc"

# A refusal leaves an earlier approval as it was.
ca_contract "$ap" appr
ca_approve "$ap" appr
cp "$store/appr.sha256" "$aux/appr.sha.keep"
printf '<task-id>\n' >> "$ac"
ca_run 1 "script: a refusal keeps the record" "$ap" appr "placeholders"
cmp -s "$store/appr.sha256" "$aux/appr.sha.keep" && ok "guard: approval: script: record unchanged" \
  || bad "guard: approval: script: record unchanged"

# --- Clean up ---
g "$fx" worktree remove --force "$ap"
g "$fx" worktree remove --force "$fe"
g "$fx" worktree remove --force "$fx/.worktrees/early"
g "$fx" branch -qD task/appr task/early feature/ca
rm -f "$store/appr.sha256" "$store/early.sha256" "$fx/.agent/contracts/early.md"

# --- For the case files after this one ---
# They share task/demo and write this exact contract, so it has to be the approved one. Stub PATHs
# need a hash tool now, or those rows would fail closed on it and prove nothing about what they test.
printf '# Contract: demo\n## Target files\n- src/app.py\n' > "$wt/.agent/contracts/demo.md"
ca_approve "$wt" demo
# Off task/*, so active-task alone switches the contract on, as these rows assume.
g "$wt" branch -qm task/demo feature/demo
tool_dir() {
  local d="$aux/$1" t; shift; mkdir -p "$d"
  for t in "$@" shasum sha256sum; do
    command -v "$t" >/dev/null 2>&1 && ln -sf "$(command -v "$t")" "$d/$t"
  done
  echo "$d"
}
