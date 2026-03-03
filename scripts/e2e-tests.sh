#!/usr/bin/env bash
###############################################################################
# e2e-tests.sh — End-to-End Validation Tests
# marciobolsoni.cloud GitOps CI/CD Suite
#
# Usage: ./e2e-tests.sh <base-url>
###############################################################################

set -euo pipefail

BASE_URL="${1:-https://staging.marciobolsoni.cloud}"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log_info()    { echo -e "\033[0;34m[E2E]\033[0m     $*"; }
log_success() { echo -e "${GREEN}[PASS]${NC}    $*"; }
log_fail()    { echo -e "${RED}[FAIL]${NC}    $*" >&2; }

PASS=0
FAIL=0

run_test() {
  local name="$1"
  local cmd="$2"
  local expected="$3"
  
  RESULT=$(eval "${cmd}" 2>/dev/null || echo "ERROR")
  
  if echo "${RESULT}" | grep -q "${expected}"; then
    log_success "${name}"
    ((PASS++)) || true
  else
    log_fail "${name} — Expected: '${expected}', Got: '${RESULT}'"
    ((FAIL++)) || true
  fi
}

echo ""
log_info "Running E2E tests against: ${BASE_URL}"
echo "─────────────────────────────────────────────"

# Core functionality tests
run_test "Homepage loads successfully" \
  "curl -sf --max-time 15 -o /dev/null -w '%{http_code}' '${BASE_URL}/'" \
  "200"

run_test "Health check endpoint" \
  "curl -sf --max-time 10 '${BASE_URL}/health' | jq -r '.status'" \
  "healthy"

run_test "API readiness probe" \
  "curl -sf --max-time 10 '${BASE_URL}/ready' | jq -r '.ready'" \
  "true"

run_test "Content-Type header is correct" \
  "curl -sf --max-time 10 -I '${BASE_URL}/' | grep -i 'content-type'" \
  "text/html"

run_test "HSTS header present" \
  "curl -sf --max-time 10 -I '${BASE_URL}/' | grep -i 'strict-transport-security'" \
  "max-age"

run_test "CSP header present" \
  "curl -sf --max-time 10 -I '${BASE_URL}/' | grep -i 'content-security-policy'" \
  "default-src"

run_test "Gzip compression enabled" \
  "curl -sf --max-time 10 -H 'Accept-Encoding: gzip' -I '${BASE_URL}/' | grep -i 'content-encoding'" \
  "gzip"

# Performance tests
P99=$(curl -sf --max-time 10 -o /dev/null -w '%{time_total}' "${BASE_URL}/" 2>/dev/null || echo "99")
if (( $(echo "${P99} < 3.0" | bc -l) )); then
  log_success "P99 response time acceptable (${P99}s < 3.0s threshold)"
  ((PASS++)) || true
else
  log_fail "P99 response time too high: ${P99}s (threshold: 3.0s)"
  ((FAIL++)) || true
fi

echo "─────────────────────────────────────────────"
log_info "E2E Results: ${PASS} passed, ${FAIL} failed"

if [[ ${FAIL} -gt 0 ]]; then
  log_fail "❌ E2E tests FAILED"
  exit 1
else
  log_success "✅ All E2E tests PASSED"
  exit 0
fi
