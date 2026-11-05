# verify.sh detection: pytest is chosen only when real Python tests exist. Sourced by run.sh; uses
# ok/bad, tool_dir and $aux. Each project is a fresh dir under $aux (removed on exit), run with a
# PATH of a stub pytest plus the few tools verify.sh needs, so nothing on the host changes the result.
vd_bin="$(tool_dir verify-detect bash dirname git date sed tail find grep cut sort cat head tr)"
printf '#!/bin/sh\necho ran >> "$VD_LOG"\nexit 0\n' > "$vd_bin/pytest"; chmod +x "$vd_bin/pytest"
# vd_run <name> <want exit> <want pytest ran: 0|1> <files…> : builds a Python project holding these files
vd_run() {
  local name="$1" want="$2" ran="$3" d f out got n=0; shift 3
  d="$(mktemp -d "$aux/vd.XXXXXX")"; : > "$d/pyproject.toml"; : > "$d/vd.log"
  mkdir -p "$d/scripts"; cp "$ROOT/scripts/verify.sh" "$d/scripts/verify.sh"
  for f in "$@"; do mkdir -p "$d/$(dirname "$f")"; : > "$d/$f"; done
  out="$( cd "$d" && unset HARNESS_MAINTAINER; VD_LOG="$d/vd.log" PATH="$vd_bin" bash scripts/verify.sh 2>&1 )"; got=$?
  [ -s "$d/vd.log" ] && n=1
  if [ "$got" = "$want" ] && [ "$n" = "$ran" ]; then ok "verify: detect: $name"
  else bad "verify: detect: $name (want exit $want ran $ran, got exit $got ran $n: $out)"; fi
}
vd_run "no tests dir is exit 78"                           78 0
vd_run "tests/harness alone is exit 78, not pytest"        78 0 tests/harness/run.sh tests/harness/test_x.py
vd_run "tests/ with no Python tests is exit 78"            78 0 tests/README.md tests/data.json
vd_run "tests/test_*.py runs pytest"                        0 1 tests/test_a.py
vd_run "tests/*_test.py runs pytest"                        0 1 tests/b_test.py
vd_run "nested test file runs pytest"                       0 1 tests/unit/test_c.py
vd_run "real tests beside tests/harness run pytest"         0 1 tests/harness/run.sh tests/test_d.py
