#!/usr/bin/env bash
#
# mayhem/test.sh — RUN libheif's own Catch2 unit tests (built by mayhem/build.sh into build/tests).
# Each test executable's Catch2 summary is parsed (not just its exit status), so a program that is
# neutered to exit(0) produces no summary and fails here.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

BUILD="$SRC/build/tests"
[ -d "$BUILD/tests" ] || { echo "test binaries missing: run mayhem/build.sh first" >&2; emit_ctrf catch2 0 1 0; exit 1; }

passed=0; failed=0; skipped=0
cd "$BUILD"
# One ctest entry per Catch2 executable (run from the ctest working dir, as upstream's add_test does).
names="$(ctest -N | sed -n 's/^ *Test *#[0-9]*: *//p')"
[ -n "$names" ] || { echo "no tests registered" >&2; emit_ctrf catch2 0 1 0; exit 1; }
cd "$BUILD/tests"
for t in $names; do
  if [ ! -x "./$t" ]; then echo "FAIL $t: binary missing"; failed=$((failed+1)); continue; fi
  out="$(timeout 600 "./$t" 2>&1)"; rc=$?
  echo "$out" | tail -3
  if echo "$out" | grep -Eq 'test cases?: +[0-9]+ \| +[0-9]+ skipped *$'; then
    skipped=$((skipped+1))     # every case skipped (codec not built in); Catch2 exits 4
  elif [ $rc -ne 0 ]; then
    echo "FAIL $t (exit $rc)"; failed=$((failed+1))
  elif echo "$out" | grep -Eq 'All tests passed \([0-9]+ assertions? in [0-9]+ test cases?\)|test cases?: +[0-9]+ \| +[0-9]+ passed( \| +[0-9]+ skipped)? *$'; then
    passed=$((passed+1))
  else
    echo "FAIL $t: no Catch2 pass summary in output"; failed=$((failed+1))
  fi
done
emit_ctrf catch2 "$passed" "$failed" "$skipped"
