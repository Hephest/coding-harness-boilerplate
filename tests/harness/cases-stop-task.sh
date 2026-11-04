# Cases: the Stop gate and the guard agree on which task is active. Sourced by run.sh.

# The receipt check goes by the branch's task, like the guard, not by a file the agent can rewrite.
# Set again: st is a short name, and case files between here and run.sh reuse it.
st="$fx/.worktrees/stop"
verify_exits 0
mkdir -p "$st/.agent/contracts" "$st/.agent/receipts" "$st/.agent/state"
printf '# Contract: stop\n\n## Target files\n- src/*\n' > "$st/.agent/contracts/stop.md"
rm -f "$st/.agent/state/active-task" "$st/.agent/receipts/stop.md"
stop 2 "effective task: no active-task, no receipt"        stask1 false "receipts/stop.md is missing"
: > "$st/.agent/state/active-task"
stop 2 "effective task: blank active-task, no receipt"     stask2 false "receipts/stop.md is missing"
echo other > "$st/.agent/state/active-task"
: > "$st/.agent/receipts/other.md"
stop 2 "effective task: another task's receipt won't do"   stask3 false "receipts/stop.md is missing"
: > "$st/.agent/receipts/stop.md"
stop 0 "effective task: its own receipt ends it"           stask4
rm -f "$st/.agent/state/active-task" "$st/.agent/receipts/stop.md" "$st/.agent/receipts/other.md" \
      "$st/.agent/contracts/stop.md"

# Off task/*, active-task is all there is, so naming a task with no contract still blocks.
g "$fx" worktree add -q -b feature/ghost "$fx/.worktrees/ghost" HEAD
ghost="$fx/.worktrees/ghost"
mkdir -p "$ghost/.agent/state"
echo ghost > "$ghost/.agent/state/active-task"
guard 2 "ghost active-task off task branch" "$ghost/src/app.py"
