#!/usr/bin/env bash
# Tests for .github/workflows/secret-scan.yml. They execute the workflow's own step
# scripts (extracted by step id) against stubbed tools, the way the runner does:
# `bash -e -o pipefail`. RUN_NETWORK_TESTS=1 adds real-engine tests (real TruffleHog,
# canary credential fetched at run time from trufflesecurity/test_keys).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
wf="$(dirname "$here")/.github/workflows/secret-scan.yml"
SENTINEL="SENTINEL_RAW_DO_NOT_PRINT"
passed=0; failed=0

script_of() { python3 "$here/extract_step.py" "$wf" "$1"; }
env_of()    { python3 "$here/extract_step.py" "$wf" "$1" --env "$2"; }
ok()  { passed=$((passed + 1)); echo "ok   - $1"; }
bad() { failed=$((failed + 1)); echo "FAIL - $1"; }
check() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
has()    { grep -qF -- "$2" <<<"$1"; }
hasnt()  { ! grep -qF -- "$2" <<<"$1"; }

new_repo() {  # prints the path of a 2-commit repo; the base is HEAD~1
  local d; d="$(mktemp -d)"
  git -C "$d" init -q -b main
  git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m head
  echo "$d"
}

# run_scan <pass1-fixture> <pass2-fixture> [stub-rc] — sets out, summary, rc, args
run_scan() {
  local repo tmp base
  repo="$(new_repo)"; tmp="$(mktemp -d)"
  base="$(git -C "$repo" rev-parse HEAD~1)"
  mkdir -p "$tmp/bin" && cp "$here/stubs/trufflehog" "$tmp/bin/"
  set +e
  out="$(cd "$repo" && PATH="$tmp/bin:$PATH" RUNNER_TEMP="$tmp/rt" GITHUB_STEP_SUMMARY="$tmp/summary.md" \
    BASE_SHA="${BASE_OVERRIDE:-$base}" EXCLUDE_PATHS="${EXCLUDE_OVERRIDE:-$(env_of scan EXCLUDE_PATHS)}" \
    STUB_PASS1="$here/fixtures/$1" STUB_PASS2="$here/fixtures/$2" STUB_RC="${3:-0}" STUB_ARGS_LOG="$tmp/args" \
    bash -e -o pipefail -c "$(script_of scan)" 2>&1)"
  rc=$?
  set -e
  summary="$(cat "$tmp/summary.md" 2>/dev/null || true)"
  args="$(cat "$tmp/args" 2>/dev/null || true)"
  rm -rf "$repo" "$tmp"
}

no_leak() { hasnt "$out" "$SENTINEL" && hasnt "$summary" "$SENTINEL"; }

# ---- scan step: unit tests (U1-U11) ----
run_scan empty.ndjson empty.ndjson
check "U1 clean PR passes"                 test "$rc" -eq 0
check "U1 clean PR: no error annotation"   hasnt "$out" "::error"
check "U1 clean PR: summary says so"       has "$summary" "No verified credentials introduced."

run_scan verified.ndjson verified.ndjson
check "U2 verified blocks"                 test "$rc" -eq 1
check "U2 error annotation at file:line"   has "$out" "::error file=app/settings.py,line=12,title=Verified credential (AWS)::"
check "U2 not reported as suppressed"      hasnt "$out" "Suppressed verified credential"
check "U2 no secret material printed"      no_leak

run_scan empty.ndjson verified.ndjson
check "U3 suppressed verified passes"      test "$rc" -eq 0
check "U3 suppressed is surfaced"          has "$out" "::warning file=app/settings.py,line=12,title=Suppressed verified credential (AWS)::"
check "U3 no secret material printed"      no_leak

run_scan unknown.ndjson empty.ndjson
check "U4 unknown does not block"          test "$rc" -eq 0
check "U4 unknown is a warning"            has "$out" "::warning file=config/db.yml,line=3,title=Possible credential (JDBC)::"
check "U4 VerificationError not printed"   no_leak

run_scan comma-path.ndjson comma-path.ndjson
check "U5 annotation properties escaped"   has "$out" "file=odd%2Cname%3Ax.py,line=7"

run_scan verified-dup.ndjson verified-dup.ndjson
check "U6 duplicates collapse to one"      test "$(grep -c '^::error' <<<"$out")" -eq 1

run_scan verified.ndjson verified.ndjson 2
check "U7 engine error is inconclusive"    test "$rc" -eq 1
check "U7 says inconclusive, not finding"  has "$out" "Secret scan inconclusive"
check "U7 engine log withheld"             no_leak

BASE_OVERRIDE="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" run_scan empty.ndjson empty.ndjson
check "U8 unreachable base is inconclusive" has "$out" "Secret scan inconclusive"
check "U8 exits non-zero"                  test "$rc" -eq 1

run_scan many.ndjson many.ndjson
check "U9 summary lists all 12 findings"   test "$(grep -c '^| AWS |' <<<"$summary")" -eq 12

run_scan empty.ndjson empty.ndjson
check "U10 pass 1 flags"                   has "$args" "--results=verified,unknown"
check "U10 pass 2 flags"                   has "$args" "--results=verified --no-ignore-tag"
check "U10 scans the PR range only"        has "$args" "--since-commit"
check "U10 comment-only allowlist: no --exclude-paths" hasnt "$args" "--exclude-paths"

EXCLUDE_OVERRIDE=$'# comment\n^vendor/' run_scan empty.ndjson empty.ndjson
check "U11 allowlist entry passes --exclude-paths" has "$args" "--exclude-paths"

# ---- range step ----
run_range() {  # <event> <base> <head>
  local tmp; tmp="$(mktemp -d)"
  set +e
  out="$(EVENT_NAME="$1" PR_BASE="$2" PR_HEAD="$3" MG_BASE="$2" MG_HEAD="$3" GITHUB_OUTPUT="$tmp/o" \
    bash -e -o pipefail -c "$(script_of range)" 2>&1)"; rc=$?
  set -e
  gh_out="$(cat "$tmp/o" 2>/dev/null || true)"; rm -rf "$tmp"
}
A=0123456789abcdef0123456789abcdef01234567; B=89abcdef0123456789abcdef0123456789abcdef
run_range pull_request "$A" "$B"
check "R-PR resolves range"  test "$gh_out" = $'base='"$A"$'\nhead='"$B"
run_range merge_group "$A" "$B"
check "R-MG resolves range"  test "$rc" -eq 0
run_range push "$A" "$B"
check "R-unsupported event inconclusive" has "$out" "Secret scan inconclusive"
run_range pull_request "" "$B"
check "R-empty sha inconclusive" has "$out" "Secret scan inconclusive"

# ---- install step ----
run_install() {  # <curl-rc>
  local tmp; tmp="$(mktemp -d)"; mkdir -p "$tmp/bin" "$tmp/rt" && cp "$here/stubs/curl" "$tmp/bin/"
  set +e
  out="$(PATH="$tmp/bin:$PATH" RUNNER_TEMP="$tmp/rt" GITHUB_PATH="$tmp/p" STUB_CURL_RC="$1" \
    TH_VERSION="$(env_of install TH_VERSION)" TH_SHA256="$(env_of install TH_SHA256)" \
    bash -e -o pipefail -c "$(script_of install)" 2>&1)"; rc=$?
  set -e; rm -rf "$tmp"
}
run_install 0
check "I1 checksum mismatch is inconclusive" has "$out" "checksum mismatch"
check "I1 exits non-zero" test "$rc" -eq 1
run_install 22
check "I2 download failure is inconclusive" has "$out" "Secret scan inconclusive"

# ---- real-engine tests (network) ----
if [[ "${RUN_NETWORK_TESTS:-0}" == "1" ]]; then
  tmp="$(mktemp -d)"; mkdir -p "$tmp/rt"
  RUNNER_TEMP="$tmp/rt" GITHUB_PATH="$tmp/path" TH_VERSION="$(env_of install TH_VERSION)" \
    TH_SHA256="$(env_of install TH_SHA256)" bash -e -o pipefail -c "$(script_of install)"
  thbin="$(cat "$tmp/path")"
  check "N0 real binary installs" test -x "$thbin/trufflehog"
  # Canary: a live basic-auth URL TruffleHog verifies as valid. Fetched, never committed.
  canary="$(curl -fsSL https://raw.githubusercontent.com/trufflesecurity/test_keys/main/keys | grep -Eo 'https://[^ ]+:[^ ]+@[^ ]+' | head -1)"
  [[ -n "$canary" ]] || { echo "could not fetch canary"; exit 1; }

  # run_real <setup-fn> — repo with one base commit; setup-fn builds the history and
  # may write a different base SHA to $BASEFILE (simulating the PR's base.sha).
  run_real() {
    local repo rt base; repo="$(mktemp -d)"; rt="$(mktemp -d)"
    git -C "$repo" init -q -b main
    git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
    base="$(git -C "$repo" rev-parse HEAD)"
    (cd "$repo" && BASEFILE="$rt/base" "$1")
    if [[ -s "$rt/base" ]]; then base="$(cat "$rt/base")"; fi
    set +e
    out="$(cd "$repo" && PATH="$thbin:$PATH" RUNNER_TEMP="$rt" GITHUB_STEP_SUMMARY="$rt/summary.md" \
      BASE_SHA="$base" EXCLUDE_PATHS="${EXCLUDE_OVERRIDE:-}" \
      bash -e -o pipefail -c "$(script_of scan)" 2>&1)"; rc=$?
    set -e
    summary="$(cat "$rt/summary.md" 2>/dev/null || true)"
    rm -rf "$repo" "$rt"
  }
  c() { git -c user.email=t@t -c user.name=t commit -q -m "$1"; }
  # Match the credential itself (`user:pass@`), not the whole URL: TruffleHog's Raw
  # is a prefix of the canary, so a full-URL match would miss a real leak.
  cred="$(grep -Eo '//[^/@]+:[^/@]+@' <<<"$canary")"; cred="${cred#//}"
  [[ -n "$cred" ]] || { echo "could not isolate canary credential"; exit 1; }
  leak_free() { hasnt "$out" "$cred" && hasnt "$summary" "$cred"; }

  r1() { echo "url = \"$canary\"" > app.cfg; git add app.cfg; c secret; }
  run_real r1
  check "R1 real verified secret blocks" test "$rc" -eq 1
  check "R1 real run prints no secret"   leak_free

  # The secret predates the PR (already on main when the branch was cut); main then
  # advanced, so the PR's base.sha is NOT an ancestor of HEAD. Only the PR's own
  # commits may be scanned — the old secret must not be blamed on this PR.
  # (Pins behaviour, not mechanism: TruffleHog's --since-commit already has
  # base..HEAD semantics, so this also passes without the workflow's merge-base,
  # which is kept as an explicit, engine-independent guard.)
  r2() { echo "url = \"$canary\"" > old.cfg; git add old.cfg; c old-secret
         git switch -q -c feature; echo ok > a.txt; git add a.txt; c clean
         git switch -q main; echo more > b.txt; git add b.txt; c main-advanced
         git rev-parse main > "$BASEFILE"; git switch -q feature; }
  run_real r2
  check "R2 pre-existing secret + advanced base is not blamed on PR" test "$rc" -eq 0

  r3() { echo "url = \"$canary\" # trufflehog:ignore" > app.cfg; git add app.cfg; c ignored; }
  run_real r3
  check "R3 real ignore tag passes"        test "$rc" -eq 0
  check "R3 real ignore tag is surfaced"   has "$out" "Suppressed verified credential"
  check "R3 real run prints no secret"     leak_free

  r4() { mkdir -p vendor; echo "url = \"$canary\"" > vendor/x.cfg; git add vendor; c vendored; }
  EXCLUDE_OVERRIDE='^vendor/' run_real r4
  check "R4 central allowlist excludes path" test "$rc" -eq 0
  rm -rf "$tmp"
fi

echo "passed=$passed failed=$failed"
[[ $failed -eq 0 ]]
