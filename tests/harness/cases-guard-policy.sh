# Sourced by run.sh: path policy cases (contract v02-guard-policy).
# Uses run.sh's helpers and fixture. Leaves active-task and the contract files as it found them.

# The hooks need one JSON reader, and either will do. git is left out or stubbed per case.
jp=jq; command -v jq >/dev/null 2>&1 || jp=python3
hook_in() { # hook_in <cwd> <key> <path>
  printf '{"tool_name":"Write","cwd":"%s","tool_input":{"%s":"%s"}}' "$1" "$2" "$3"
}

# --- Criterion 1: one shared function, callable with a path and a cwd ---
policy() { # policy <expected-exit> <name> <path> <cwd>
  local got
  got="$( unset HARNESS_MAINTAINER HARNESS_ROLE
          HOOK_INPUT=''; . "$fx/.claude/hooks/_lib.sh"
          cd "$aux" && path_policy "$3" "$4" >/dev/null 2>&1; echo $? )"
  if [ "$got" = "$1" ]; then ok "guard: policy: $2"; else bad "guard: policy: $2 (want exit $1, got $got)"; fi
}
policy 0 "direct call allows"           "src/app.py" "$wt"
policy 2 "direct call blocks"           ".env"       "$wt"
policy 2 "direct call: cwd picks the branch" "src/app.py" "$fx"
if grep -qE 'canon_path|repo_root|case "\$rel"' "$ROOT/.claude/hooks/guard-write.sh"; then
  bad "guard: policy: guard-write.sh keeps no policy of its own"
else
  ok "guard: policy: guard-write.sh keeps no policy of its own"
fi

# Relative paths resolve against the hook's .cwd, not the hook process's $PWD
guard_raw 0 "cwd: relative path in a worktree" "$PATH" "$(hook_in "$wt" file_path src/app.py)"
guard_raw 2 "cwd: relative path on main"       "$PATH" "$(hook_in "$fx" file_path src/app.py)" "you are on main"
guard_raw 2 "cwd: relative secret"             "$PATH" "$(hook_in "$wt" file_path .env)"       "protected path"

# --- Criterion 2: git missing blocks, outside a repo stays allowed ---
nogit="$(tool_dir nogit cat dirname "$jp")"
badgit="$(tool_dir badgit cat dirname "$jp")"
printf '#!/bin/sh\necho "fatal: detected dubious ownership" >&2\nexit 128\n' > "$badgit/git"; chmod +x "$badgit/git"
guard_raw 2 "git missing: repo path blocked"       "$nogit"  "$(input "$wt/src/app.py")" "git is missing"
guard_raw 2 "git missing: can't tell outside"      "$nogit"  "$(input "$aux/plain.txt")" "git is missing"
guard_raw 2 "git missing: .git check still first"  "$nogit"  "$(input "$fx/.git/config")" "git internals"
guard_raw 2 "git missing: git that refuses blocks" "$badgit" "$(input "$wt/src/app.py")" "git is missing"
guard_raw 0 "git missing: outside any repo allowed" "$PATH"  "$(input "$aux/plain.txt")"
guard_raw 0 "git missing: new dir outside any repo" "$PATH"  "$(input "$aux/no/such/dir/plain.txt")"

# --- Criterion 3: NotebookEdit ---
nb() { printf '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"%s","new_source":"x"}}' "$1"; }
jqonly=""; pyonly=""
command -v jq >/dev/null 2>&1 && jqonly="$(tool_dir nb-jq cat dirname git jq)"
command -v python3 >/dev/null 2>&1 && pyonly="$(tool_dir nb-py cat dirname git python3)"
for reader in jq python; do
  if [ "$reader" = jq ]; then dir="$jqonly"; else dir="$pyonly"; fi
  if [ -z "$dir" ]; then echo "SKIP  guard: notebook: $reader (not installed)"; continue; fi
  guard_raw 0 "notebook: $reader: worktree allowed"   "$dir" "$(nb "$wt/src/n.ipynb")"
  guard_raw 2 "notebook: $reader: main blocked"       "$dir" "$(nb "$fx/src/n.ipynb")" "you are on main"
  guard_raw 2 "notebook: $reader: secrets blocked"    "$dir" "$(nb "$wt/.env")"        "protected path"
  guard_raw 2 "notebook: $reader: harness blocked"    "$dir" "$(nb "$wt/.claude/hooks/n.ipynb")" "harness infrastructure"
  guard_raw 2 "notebook: $reader: file_path read first" "$dir" \
    "{\"tool_input\":{\"file_path\":\"$wt/.env\",\"notebook_path\":\"$wt/src/n.ipynb\"}}" "protected path"
done

# Both events match it. Plain names and | are an exact list, so the name must be spelled out.
settings_matchers() { # settings_matchers <event>: the matcher of the hook that runs <script>
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg s "$2" ".hooks.$1[] | select(any(.hooks[]; .command | contains(\$s))) | .matcher" "$ROOT/.claude/settings.json"
  else
    python3 -c 'import json,sys; print(*[e.get("matcher","") for e in json.load(open(sys.argv[1]))["hooks"][sys.argv[2]] if any(sys.argv[3] in h["command"] for h in e["hooks"])], sep="\n")' \
      "$ROOT/.claude/settings.json" "$1" "$2"
  fi
}
for pair in PreToolUse:guard-write.sh PostToolUse:post-edit-check.sh; do
  m="|$(settings_matchers "${pair%%:*}" "${pair##*:}")|"
  for tool in Edit Write MultiEdit NotebookEdit; do
    case "$m" in *"|$tool|"*) ok "guard: notebook: ${pair%%:*} matches $tool" ;;
                 *) bad "guard: notebook: ${pair%%:*} matches $tool (matcher $m)" ;; esac
  done
done

# PostToolUse: a notebook reaches the sensor. The stub verify.sh records what it was handed.
post() { # post <name> <input> <file the sensor must get, "" = must not run>
  local got
  : > "$aux/post.log"
  cp "$st/scripts/verify.sh" "$aux/verify.real"
  printf '#!/bin/sh\necho "$2" >> "%s/post.log"\n' "$aux" > "$st/scripts/verify.sh"
  printf '%s' "$2" | "$st/.claude/hooks/post-edit-check.sh" >/dev/null 2>&1
  cp "$aux/verify.real" "$st/scripts/verify.sh"
  got="$(cat "$aux/post.log")"
  if [ "$got" = "$3" ]; then ok "guard: notebook: post: $1"; else bad "guard: notebook: post: $1 (want '$3', got '$got')"; fi
}
echo '{}' > "$st/src/n.ipynb"
post "notebook_path checked" "$(nb "$st/src/n.ipynb")"                  "$st/src/n.ipynb"
post "file_path still checked" "$(input "$st/src/n.ipynb")"             "$st/src/n.ipynb"
post "relative path uses .cwd" "$(hook_in "$st" notebook_path src/n.ipynb)" "$st/src/n.ipynb"
post "missing file skipped"  "$(nb "$st/src/gone.ipynb")"               ""
rm -f "$st/src/n.ipynb"

# --- Criterion 4: no path ---
for reader in jq python; do
  if [ "$reader" = jq ]; then dir="$jqonly"; else dir="$pyonly"; fi
  [ -n "$dir" ] || continue
  guard_raw 2 "empty path: $reader: no path key"   "$dir" '{"tool_name":"Write","tool_input":{"content":"x"}}' "names no file"
  guard_raw 2 "empty path: $reader: empty string"  "$dir" '{"tool_input":{"file_path":""}}' "names no file"
  guard_raw 2 "empty path: $reader: no tool_input" "$dir" '{"tool_name":"Write"}' "names no file"
  guard_raw 0 "empty path: $reader: empty stdin"   "$dir" ""
done
guard_raw 0 "empty path: empty stdin, no reader"   "$(tool_dir ep-bare cat dirname)" ""

# --- Criterion 5: behaviour-shaping files ---
guard 2 "behaviour-shaping: root CLAUDE.md"        "$wt/CLAUDE.md"
guard 2 "behaviour-shaping: rules"                 "$wt/.claude/rules/auth.md"
guard 2 "behaviour-shaping: nested rules"          "$wt/.claude/rules/a/b.md"
guard 2 "behaviour-shaping: harness-init"          "$wt/scripts/harness-init.sh"
guard 0 "behaviour-shaping: maintainer CLAUDE.md"  "$wt/CLAUDE.md" maint
guard 0 "behaviour-shaping: maintainer rules"      "$wt/.claude/rules/auth.md" maint
guard 0 "behaviour-shaping: maintainer harness-init" "$wt/scripts/harness-init.sh" maint
guard 0 "behaviour-shaping: module CLAUDE.md"      "$wt/src/CLAUDE.md"
guard 0 "behaviour-shaping: other script"          "$wt/scripts/other.sh"
guard 0 "behaviour-shaping: lessons in a worktree" "$wt/.agent/lessons.md"
guard 0 "behaviour-shaping: lessons on main"       "$fx/.agent/lessons.md"
