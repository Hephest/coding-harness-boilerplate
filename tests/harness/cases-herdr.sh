# herdr-sub.sh edge cases: orphaned tabs, argument parsing, quoting, and interactive waiting.
# Sourced by run.sh after its own herdr cases; uses ok/bad/tool_dir and the $wt/$aux fixtures.
# The stub below is its own copy, so it can model agent state without touching run.sh's stub.
hx="$(tool_dir herdr-edge-stub)"
cat > "$hx/herdr" <<'STUB'
#!/usr/bin/env bash
# Logs one line per call. Prompt text goes to files so quotes and newlines survive intact.
echo "$*" >> "$HERDR_STUB_DIR/log"
st="$HERDR_STUB_DIR/state"
case "$1 $2" in
  "tab create") if [ -n "${STUB_TAB_JSON:-}" ]; then echo "$STUB_TAB_JSON"
                else echo '{"result":{"tab":{"tab_id":"t1"},"root_pane":{"pane_id":"p1"}}}'; fi ;;
  "pane run")   env -u HARNESS_MAINTAINER bash -c "$4" ;;
  "agent start") echo idle > "$st" ;;
  "agent prompt") printf '%s' "$4" > "$HERDR_STUB_DIR/prompt"; echo submitted > "$st" ;;
  "agent wait")
    # Real herdr matches the current state, so a freshly prompted agent still reads as idle.
    case " $* " in
      *" --until working "*)
        if [ "$(cat "$st")" = submitted ]; then
          if [ "${STUB_MODE:-}" = blocked ]; then echo blocked > "$st"; echo '{"status":"blocked"}'; else echo working > "$st"; echo '{"status":"working"}'; fi
        else exit 1; fi ;;
      *)
        case "$(cat "$st")" in
          working) echo finished > "$st"; echo '{"status":"idle"}' ;;
          blocked) echo '{"status":"blocked"}' ;;
          *)       echo early >> "$HERDR_STUB_DIR/log"; echo '{"status":"idle"}' ;;
        esac ;;
    esac ;;
  "agent read") if [ "$(cat "$st")" = finished ]; then echo REPORT-FINAL; else echo REPORT-EARLY; fi ;;
esac
exit 0
STUB
cat > "$hx/claude" <<'STUB'
#!/usr/bin/env bash
pwd -P > "$HERDR_STUB_DIR/claude.cwd"
cat > "$HERDR_STUB_DIR/claude.stdin"
echo "ran"
STUB
chmod +x "$hx/herdr" "$hx/claude"

# hx_sub <repo> <stub mode> <args…>: runs herdr-sub.sh in <repo> against the stub; stdout in $hx_out.
# The stub dir is reset every call. Exit status is the script's.
hx_sub() {
  local repo="$1" mode="$2"; shift 2
  rm -rf "$hx/run"; mkdir -p "$hx/run"
  hx_out="$( cd "$repo" || exit 1
    HERDR_ENV=1 HERDR_WORKSPACE_ID=w1 HERDR_STUB_DIR="$hx/run" STUB_MODE="$mode" STUB_TAB_JSON="${STUB_TAB_JSON:-}" \
      PATH="$hx:$PATH" "$ROOT/scripts/herdr-sub.sh" "$@" 2>"$hx/stderr" )"
}
hx_check() { # hx_check <name> <want exit> <got exit> [extra failure detail]
  if [ "$2" = "$3" ]; then ok "herdr-sub: $1"; else bad "herdr-sub: $1 (want exit $2, got $3 ${4:-})"; fi
}

# ---- orphan: a tab whose pane id can't be parsed must not be left open ----
STUB_TAB_JSON='{"result":{"tab":{"tab_id":"t9"}}}' hx_sub "$wt" "" start demo hello; rc=$?
if [ "$rc" = 2 ] && grep -q '^tab close t9' "$hx/run/log"; then ok "herdr-sub: orphan: tab closed when pane id is unreadable"
else bad "herdr-sub: orphan: tab closed when pane id is unreadable (exit $rc, log: $(tr '\n' ';' < "$hx/run/log"))"; fi

# ---- args ----
hx_sub "$wt" "" start demo hello --timeout; hx_check "args: --timeout without value" 2 $?
hx_sub "$wt" "" start demo hello --timeout abc; hx_check "args: --timeout not a number" 2 $?
hx_sub "$wt" "" start demo hello --timeout --keep; hx_check "args: --timeout swallowing an option" 2 $?
hx_sub "$wt" "" start demo hello --bogus; hx_check "args: unknown option" 2 $?
hx_sub "$wt" "" start demo; hx_check "args: missing prompt" 2 $?
hx_sub "$wt" "" start demo hello extra; hx_check "args: extra positional" 2 $?
hx_sub "$wt" "" wait; hx_check "args: wait without id" 2 $?
hx_sub "$wt" "" start --timeout 4321 demo hello --keep; rc=$?
id="$hx_out"
if [ "$rc" = 0 ] && grep -qx 'timeout=4321' "$wt/.agent/state/runs/$id/meta" && grep -qx 'keep=1' "$wt/.agent/state/runs/$id/meta"
then ok "args: options before and after positionals"; else bad "args: options before and after positionals (exit $rc)"; fi

# wait accepts --timeout before or after the id; a bad value is a usage error.
hx_sub "$wt" "" start demo hello --interactive; id="$hx_out"
for order in "--timeout 1234 $id" "$id --timeout 1234"; do
  echo submitted > "$hx/run/state"
  # shellcheck disable=SC2086
  ( cd "$wt" && HERDR_ENV=1 HERDR_WORKSPACE_ID=w1 HERDR_STUB_DIR="$hx/run" PATH="$hx:$PATH" \
      "$ROOT/scripts/herdr-sub.sh" wait $order >/dev/null 2>&1 ); rc=$?
  if [ "$rc" = 0 ] && grep -q 'agent wait .*--timeout 1234' "$hx/run/log"; then ok "args: wait '$order'"
  else bad "args: wait '$order' (exit $rc)"; fi
done
( cd "$wt" && HERDR_ENV=1 HERDR_WORKSPACE_ID=w1 HERDR_STUB_DIR="$hx/run" PATH="$hx:$PATH" \
    "$ROOT/scripts/herdr-sub.sh" wait "$id" --timeout >/dev/null 2>&1 ); hx_check "args: wait --timeout without value" 2 $?
( cd "$wt" && HERDR_ENV=1 HERDR_WORKSPACE_ID=w1 HERDR_STUB_DIR="$hx/run" PATH="$hx:$PATH" \
    "$ROOT/scripts/herdr-sub.sh" wait "$id" --timeout x >/dev/null 2>&1 ); hx_check "args: wait --timeout not a number" 2 $?

# ---- quoting: odd repo path, awkward prompt ----
odd="$aux/re po'q \$x \"y\""; mkdir -p "$odd/.claude/agents"
cp "$wt/.claude/agents/demo.md" "$odd/.claude/agents/demo.md"
prompt=$'line1 "dq" \'sq\' $HOME `date` $(id)\nline2 back\\slash\n'
hx_sub "$odd" "" run demo "$prompt"; rc=$?
if [ "$rc" = 0 ] && [ "$(cat "$hx/run/claude.cwd" 2>/dev/null)" = "$(cd "$odd" && pwd -P)" ]; then ok "herdr-sub: quoting: headless runs in a repo path with spaces and quotes"
else bad "herdr-sub: quoting: headless runs in a repo path with spaces and quotes (exit $rc: $(cat "$hx/stderr"))"; fi
if [[ "$(cat "$hx/run/claude.stdin" 2>/dev/null)" == *"${prompt%$'\n'}"* ]]; then ok "herdr-sub: quoting: headless prompt intact"
else bad "herdr-sub: quoting: headless prompt intact"; fi
hx_sub "$odd" "" start demo "$prompt" --interactive >/dev/null; rc=$?
if [ "$rc" = 0 ] && [[ "$(cat "$hx/run/prompt" 2>/dev/null)" == *"${prompt%$'\n'}"* ]]; then ok "herdr-sub: quoting: interactive prompt intact, newlines kept"
else bad "herdr-sub: quoting: interactive prompt intact, newlines kept (exit $rc)"; fi

# ---- interactive: wait returns only after the session finished ----
hx_sub "$wt" "" run demo hello --interactive; rc=$?
if [ "$rc" = 0 ] && [[ "$hx_out" == *REPORT-FINAL* ]] && ! grep -qx early "$hx/run/log"; then ok "herdr-sub: interactive: waits for the session to finish"
else bad "herdr-sub: interactive: waits for the session to finish (exit $rc, out: $hx_out)"; fi
hx_sub "$wt" blocked run demo hello --interactive; rc=$?
hx_check "interactive: blocked session exits 3" 3 "$rc"
