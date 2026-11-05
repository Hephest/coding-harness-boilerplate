#!/usr/bin/env bash
# Run a .claude/agents/<role> subagent as a background Herdr task in its own hidden tab.
# The main agent's pane is never used: no output, no focus change, no TUI in it.
#
#   scripts/herdr-sub.sh run   <role> <prompt|@file> [opts]  start, wait, print report, close tab
#   scripts/herdr-sub.sh start <role> <prompt|@file> [opts]  start and print the run id (for parallel runs)
#   scripts/herdr-sub.sh wait  <run-id> [--timeout MS]        wait, print report, close tab
#   scripts/herdr-sub.sh list                                 runs and their status
#   scripts/herdr-sub.sh close <run-id>                       close a run's tab (keeps its files)
#
# opts: --timeout MS (default 600000) · --interactive (real Claude TUI in the tab; you can attach and steer)
#       --keep (leave the tab open after it finishes)
#
# Reports land in .agent/state/runs/<run-id>/report.md. Exit codes: 0 ok · 1 subagent failed
# · 3 blocked (needs you in its tab) · 124 timed out (still running) · 2 usage / not in Herdr.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
RUNS="$ROOT/.agent/state/runs"
SENTINEL="HERDR_SUB_DONE"

die() { echo "herdr-sub: $*" >&2; exit 2; }
jget() { # jget '<jq path>' <json> : first non-empty match among alternatives separated by ' , '
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$2" | jq -r "[$(printf '%s' "$1" | sed 's/\(\.[a-z_]*\)/\1?/g')] | map(select(type == \"string\" or type == \"number\")) | first // empty" 2>/dev/null
  else printf '%s' "$2" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for path in sys.argv[1].split(" , "):
    cur = d
    for k in path.strip().lstrip(".").split("."):
        cur = cur.get(k) if isinstance(cur, dict) else None
    if isinstance(cur, (str, int)):
        print(cur); break
' "$1" 2>/dev/null; fi
}
meta() { grep "^$2=" "$RUNS/$1/meta" 2>/dev/null | head -n1 | cut -d= -f2-; }
frontmatter() { awk -v k="$2" 'NR==1&&/^---/{f=1;next} f&&/^---/{exit} f&&$1==k":"{sub("^"k":[ ]*","");print;exit}' "$1"; }

need_herdr() {
  [ "${HERDR_ENV:-}" = 1 ] || die "not inside a Herdr pane (HERDR_ENV!=1). Use the built-in Agent tool instead."
  command -v herdr >/dev/null || die "herdr not on PATH"
  [ -n "${HERDR_WORKSPACE_ID:-}" ] || die "HERDR_WORKSPACE_ID not set"
}

# parse_opts <args…>: options may come before or after the positionals, in any order.
# Sets P1 P2 NPOS O_TIMEOUT O_INTERACTIVE O_KEEP. A bare `--` makes everything after it positional.
parse_opts() {
  P1=""; P2=""; NPOS=0; O_TIMEOUT=""; O_INTERACTIVE=0; O_KEEP=0
  local endopts=0
  while [ $# -gt 0 ]; do
    if [ "$endopts" = 0 ]; then case "$1" in
      --timeout)
        [ $# -ge 2 ] || die "--timeout needs a value (milliseconds)"
        case "$2" in ''|*[!0-9]*) die "--timeout needs a number of milliseconds, got '$2'" ;; esac
        O_TIMEOUT="$2"; shift 2; continue ;;
      --interactive) O_INTERACTIVE=1; shift; continue ;;
      --keep) O_KEEP=1; shift; continue ;;
      --) endopts=1; shift; continue ;;
      -*) die "unknown option $1" ;;
    esac; fi
    NPOS=$((NPOS + 1))
    case "$NPOS" in 1) P1="$1" ;; 2) P2="$1" ;; *) die "unexpected argument '$1'" ;; esac
    shift
  done
}

cmd_start() {
  parse_opts "$@"
  [ "$NPOS" = 2 ] || die "usage: start <role> <prompt|@file> [--timeout MS] [--interactive] [--keep]"
  local role="$P1" prompt="$P2" timeout="${O_TIMEOUT:-600000}" mode=headless keep="$O_KEEP"
  [ "$O_INTERACTIVE" = 1 ] && mode=interactive
  need_herdr
  local agent_file="$ROOT/.claude/agents/$role.md"
  [ -f "$agent_file" ] || die "no agent '$role' in .claude/agents/"
  [ "${prompt#@}" != "$prompt" ] && { [ -f "${prompt#@}" ] || die "no file ${prompt#@}"; prompt="$(cat "${prompt#@}")"; }
  [ -n "$prompt" ] || die "empty prompt"

  local model id dir out tab pane
  model="$(frontmatter "$agent_file" model)"
  id="$(printf '%s' "$role" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9-' '-' | cut -c1-14)-$(date +%H%M%S)-$RANDOM"
  dir="$RUNS/$id"; mkdir -p "$dir"

  cat > "$dir/prompt.md" <<EOF
You are running as the \`$role\` subagent of this project, started by the main agent in a
background Herdr tab. Do only this task. Do not delegate, do not start other agents,
do not edit harness files. Your final message is the report: keep it in the format your
agent definition asks for.

## Task
$prompt
EOF

  # Maintainer mode follows the caller. The tab env reaches both modes: `herdr agent start` has no
  # env option, so an interactive session inherits it from the tab's shell.
  local maint_env=() maint_export=""
  if [ "${HARNESS_MAINTAINER:-}" = 1 ]; then
    maint_env=(--env HARNESS_MAINTAINER=1); maint_export="export HARNESS_MAINTAINER=1"
  fi

  out="$(herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$ROOT" --label "sub:$id" \
          --env "HARNESS_ROLE=$role" --env "HARNESS_RUN_ID=$id" ${maint_env[@]+"${maint_env[@]}"} \
          --no-focus 2>&1)" \
    || die "tab create failed: $out"
  tab="$(jget '.result.tab.tab_id , .result.tab.id , .result.tab' "$out")"
  pane="$(jget '.result.root_pane.pane_id , .result.root_pane.id , .result.root_pane' "$out")"
  # The tab exists from here on. Every failure below closes it, or it stays open and hidden for good.
  # Marking the run as failed keeps `list` from showing it as running forever.
  fail_start() {
    [ -z "$tab" ] || herdr tab close "$tab" >/dev/null 2>&1 || true
    echo 1 > "$dir/exit_code"
    die "$1"
  }
  [ -n "$pane" ] || fail_start "could not read root pane id from: $out"
  printf 'role=%s\nmodel=%s\nmode=%s\ntab=%s\npane=%s\nkeep=%s\ntimeout=%s\nstarted=%s\n' \
    "$role" "$model" "$mode" "$tab" "$pane" "$keep" "$timeout" "$(date '+%F %T')" > "$dir/meta"

  local model_args=(); [ -n "$model" ] && model_args=(--model "$model")
  if [ "$mode" = headless ]; then
    # Headless: report goes to a file; the tab only shows a one-line status.
    # Every value is %q-quoted: a repo path with spaces, quotes or $ must not break the script.
    local q_root q_role q_id q_dir q_model q_msg
    q_root="$(printf '%q' "$ROOT")"; q_role="$(printf '%q' "$role")"; q_id="$(printf '%q' "$id")"
    q_dir="$(printf '%q' "$dir")"; q_model="$(printf '%q' "$model")"
    q_msg="$(printf '%q' "[herdr-sub] $id ($role${model:+ on $model}) running…")"
    cat > "$dir/run.sh" <<EOF
#!/usr/bin/env bash
cd $q_root || exit 1
export HARNESS_ROLE=$q_role HARNESS_RUN_ID=$q_id
$maint_export
printf '%s\\n' $q_msg
claude -p --agent $q_role ${model:+--model $q_model} ${HERDR_SUB_CLAUDE_ARGS:-} \\
  < $q_dir/prompt.md > $q_dir/report.md 2> $q_dir/stderr.log
echo \$? > $q_dir/exit_code
echo "[herdr-sub] finished with exit \$(cat $q_dir/exit_code)"
echo "$SENTINEL"
EOF
    chmod +x "$dir/run.sh"
    herdr pane run "$pane" "bash $q_dir/run.sh" >/dev/null 2>"$dir/herdr.err" \
      || fail_start "pane run failed: $(cat "$dir/herdr.err")"
  else
    # Interactive: a real Claude session you can attach to (herdr agent focus/attach <run-id>).
    herdr agent start "$id" --kind claude --pane "$pane" --timeout 60000 -- \
      --agent "$role" ${model_args[@]+"${model_args[@]}"} >/dev/null 2>"$dir/herdr.err" \
      || fail_start "agent start failed: $(cat "$dir/herdr.err")"
    # The prompt goes in as written, newlines included: flattening them changed what the task said.
    # --wait returns on the first working/blocked state seen after submission, so the idle the agent
    # was showing before can't satisfy a later `agent wait`. If nothing is seen in 5s, herdr fails
    # with agent_prompt_stalled: report that, and close the tab, rather than a run that never began.
    herdr agent prompt "$id" "$(cat "$dir/prompt.md")" --wait --until working --until blocked \
      >/dev/null 2>>"$dir/herdr.err" \
      || fail_start "agent prompt failed (stalled or rejected): $(cat "$dir/herdr.err")"
  fi
  echo "$id"
}

cmd_wait() {
  parse_opts "$@"
  [ "$NPOS" = 1 ] && [ "$O_INTERACTIVE" = 0 ] && [ "$O_KEEP" = 0 ] || die "usage: wait <run-id> [--timeout MS]"
  local id="$P1"; [ -n "$id" ] && [ -d "$RUNS/$id" ] || die "no run '$id'"
  local timeout; timeout="$(meta "$id" timeout)"
  [ -z "$O_TIMEOUT" ] || timeout="$O_TIMEOUT"
  local dir="$RUNS/$id" mode pane tab keep role code out
  mode="$(meta "$id" mode)"; pane="$(meta "$id" pane)"; tab="$(meta "$id" tab)"
  keep="$(meta "$id" keep)"; role="$(meta "$id" role)"

  if [ "$mode" = headless ]; then
    if [ ! -f "$dir/exit_code" ]; then
      herdr pane wait-output "$pane" --match "$SENTINEL" --timeout "${timeout:-600000}" >/dev/null 2>&1
      [ -f "$dir/exit_code" ] || { echo "TIMEOUT: $id ($role) still running in tab ${tab:-?}. Re-run: scripts/herdr-sub.sh wait $id" >&2; exit 124; }
    fi
    code="$(cat "$dir/exit_code")"
  else
    # cmd_start already saw the agent leave idle (prompt --wait), so a plain wait can't match the
    # old idle. A turn that finished long ago is idle now and returns at once: start now, wait later.
    out="$(herdr agent wait "$id" --timeout "${timeout:-600000}" 2>&1)" \
      || { echo "TIMEOUT: $id ($role) still working. Re-run: scripts/herdr-sub.sh wait $id" >&2; exit 124; }
    herdr agent read "$id" --source recent-unwrapped --lines 200 > "$dir/report.md" 2>/dev/null
    if printf '%s' "$out" | grep -q '"blocked"'; then
      echo "BLOCKED: $id ($role) is waiting for input. Ask the user to open it: herdr agent focus $id" >&2
      cat "$dir/report.md"; exit 3
    fi
    code=0; echo 0 > "$dir/exit_code"
  fi

  echo "=== $role · $id · exit $code ==="
  cat "$dir/report.md" 2>/dev/null
  if [ "$code" != 0 ]; then echo "--- stderr (last 20) ---"; tail -n 20 "$dir/stderr.log" 2>/dev/null; fi
  [ "$keep" = 1 ] || [ -z "$tab" ] || herdr tab close "$tab" >/dev/null 2>&1 || true
  [ "$code" = 0 ] || exit 1
}

cmd_list() {
  [ -d "$RUNS" ] || { echo "no runs"; return; }
  for d in "$RUNS"/*/; do
    local id; id="$(basename "$d")"
    local st="running"; [ -f "$d/exit_code" ] && st="exit $(cat "$d/exit_code")"
    printf '%-32s %-12s %-11s %-8s %s\n' "$id" "$(meta "$id" role)" "$(meta "$id" mode)" "$st" "$(meta "$id" started)"
  done
}

cmd_close() {
  local id="${1:-}"; [ -d "$RUNS/$id" ] || die "no run '$id'"
  need_herdr; local tab; tab="$(meta "$id" tab)"
  [ -n "$tab" ] && herdr tab close "$tab"
}

sub="${1:-}"; shift || true
case "$sub" in
  start) cmd_start "$@" ;;
  run)   id="$(cmd_start "$@")" || exit $?; cmd_wait "$id" ;;
  wait)  cmd_wait "$@" ;;
  list)  cmd_list ;;
  close) cmd_close "$@" ;;
  *) sed -n '2,17p' "$0"; exit 2 ;;
esac
