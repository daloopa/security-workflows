#!/usr/bin/env bash
# Tests for .github/workflows/jira-traceability.yml (EI-2451, Epic EI-1686 D18).
# They execute the workflow's own `check` step script (extracted by step id)
# against a stubbed curl, the way the runner does: `bash -e -o pipefail`.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
wf="$(dirname "$here")/.github/workflows/jira-traceability.yml"
TOKEN="SENTINEL_TOKEN_DO_NOT_PRINT"
passed=0; failed=0

script_of() { python3 "$here/extract_step.py" "$wf" "$1"; }
ok()  { passed=$((passed + 1)); echo "ok   - $1"; }
bad() { failed=$((failed + 1)); echo "FAIL - $1"; }
check() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
has()    { grep -qF -- "$2" <<<"$1"; }
hasnt()  { ! grep -qF -- "$2" <<<"$1"; }

# run_check <title> <branch> [curl-rc] — sets out, summary, rc, pwned
run_check() {
  local tmp script
  tmp="$(mktemp -d)"; mkdir -p "$tmp/bin"
  cp "$here/stubs/jira-curl" "$tmp/bin/curl"
  if ! script="$(script_of check 2>&1)"; then
    out="$script"; summary=""; rc=99; pwned=no; rm -rf "$tmp"; return
  fi
  set +e
  out="$(cd "$tmp" && PATH="$tmp/bin:$PATH" TMPDIR="$tmp" GITHUB_STEP_SUMMARY="$tmp/summary.md" \
    PR_TITLE="$1" HEAD_REF="$2" JIRA_USER="svc@example.test" JIRA_TOKEN="$TOKEN" \
    JIRA_BASE_URL="https://jira.example.test" STUB_JIRA_FIXTURES="$here/fixtures/jira" \
    STUB_CURL_RC="${3:-0}" bash -e -o pipefail -c "$script" 2>&1)"
  rc=$?
  set -e
  summary="$(cat "$tmp/summary.md" 2>/dev/null || true)"
  if [[ -e "$tmp/pwned" || -e "$tmp/pwned2" ]]; then pwned=yes; else pwned=no; fi
  rm -rf "$tmp"
}

run_check "EI-100: add bucket" "EI-100/x"
check "J1 key in title and branch passes"      test "$rc" -eq 0
check "J1 summary names the ticket"            has "$summary" "EI-100"

run_check "add bucket" "feature/x"
check "J2 no key fails"                        test "$rc" -eq 1
check "J2 says no Jira key"                    has "$out" "no Jira key"

run_check "add bucket" "EI-100/x"
check "J3 branch-only key passes"              test "$rc" -eq 0

run_check "EI-999: x" "feature/x"
check "J4 unknown key fails"                   test "$rc" -eq 1
check "J4 names the key"                       has "$out" "EI-999"
check "J4 says not found"                      has "$out" "not found"

run_check "EI-200: x" "feature/x"
check "J5 Done ticket fails"                   test "$rc" -eq 1
check "J5 names the key"                       has "$out" "EI-200"
check "J5 says Done"                           has "$out" "Done"

run_check "EI-100: x" "EI-999/x"
check "J6 unknown branch key fails"            test "$rc" -eq 1
check "J6 names the branch key"                has "$out" "EI-999"

run_check "AUTH-1: x" "feature/x"
check "J7 Jira 401 fails"                      test "$rc" -eq 1
check "J7 401 is inconclusive"                 has "$out" "inconclusive"
check "J7 401 is not 'no Jira key'"            hasnt "$out" "no Jira key"
run_check "EI-100: x" "feature/x" 7
check "J7 transport failure fails"             test "$rc" -eq 1
check "J7 transport failure is inconclusive"   has "$out" "inconclusive"

# shellcheck disable=SC2016  # the $(...) must reach the step unexpanded
run_check 'EI-100: $(touch "$TMPDIR/pwned")' "feature/x"
check "J8 injected title with key passes"      test "$rc" -eq 0
check "J8 injected title runs nothing"         test "$pwned" = no
# shellcheck disable=SC2016
run_check '$(touch "$TMPDIR/pwned2")' "feature/x"
check "J8 injected title without key fails"    test "$rc" -eq 1
check "J8 injected title runs nothing (2)"     test "$pwned" = no

run_check "ei-100: x" "feature/x"
check "J9 lowercase key does not count"        test "$rc" -eq 1
check "J9 says no Jira key"                    has "$out" "no Jira key"

for t in "EI-100: x|EI-100/x" "EI-999: x|feature/x" "AUTH-1: x|feature/x"; do
  run_check "${t%%|*}" "${t##*|}"
  check "J10 token never printed (${t%%|*})"   hasnt "$out$summary" "$TOKEN"
done

echo "jira-traceability: $passed passed, $failed failed"
[[ "$failed" -eq 0 ]]
