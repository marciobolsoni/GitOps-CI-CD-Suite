#!/usr/bin/env bash
###############################################################################
# smoke-tests.sh — Post-Deployment Smoke Tests
# marciobolsoni.cloud GitOps CI/CD Suite
#
# Usage: ./smoke-tests.sh <environment> <version>
###############################################################################

set -euo pipefail

ENVIRONMENT="${1:-staging}"
VERSION="${2:-unknown}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()    { echo -e "\033[0;34m[SMOKE]\033[0m   $*"; }
log_success() { echo -e "${GREEN}[PASS]${NC}    $*"; }
log_fail()    { echo -e "${RED}[FAIL]${NC}    $*" >&2; }

if [[ "${ENVIRONMENT}" == "production" ]]; then
  BASE_URL="https://marciobolsoni.cloud"
else
  BASE_URL="https://staging.marciobolsoni.cloud"
fi

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
log_info "Running smoke tests for ${ENVIRONMENT} (version: ${VERSION})"
echo "─────────────────────────────────────────────"

# Test 1: Health endpoint
run_test "Health endpoint returns healthy" \
  "curl -sf --max-time 10 '${BASE_URL}/health' | jq -r '.status'" \
  "healthy"

# Test 2: Version endpoint matches deployed version
run_test "Version endpoint returns correct version" \
  "curl -sf --max-time 10 '${BASE_URL}/version' | jq -r '.version'" \
  "${VERSION}"

# Test 3: Homepage returns HTTP 200
run_test "Homepage returns HTTP 200" \
  "curl -sf --max-time 10 -o /dev/null -w '%{http_code}' '${BASE_URL}/'" \
  "200"

# Test 4: HTTPS redirect works
run_test "HTTP redirects to HTTPS" \
  "curl -s --max-time 10 -o /dev/null -w '%{http_code}' 'http://$(echo ${BASE_URL} | sed 's|https://||')/'" \
  "301\|302"

# Test 5: Security headers present
run_test "X-Frame-Options security header present" \
  "curl -sf --max-time 10 -I '${BASE_URL}/' | grep -i 'x-frame-options'" \
  "DENY\|SAMEORIGIN"

# Test 6: Response time under 2 seconds
RESPONSE_TIME=$(curl -sf --max-time 10 -o /dev/null -w '%{time_total}' "${BASE_URL}/" 2>/dev/null || echo "99")
if (( $(echo "${RESPONSE_TIME} < 2.0" | bc -l) )); then
  log_success "Response time under 2s (${RESPONSE_TIME}s)"
  ((PASS++)) || true
else
  log_fail "Response time too high: ${RESPONSE_TIME}s (threshold: 2.0s)"
  ((FAIL++)) || true
fi

echo "─────────────────────────────────────────────"
echo ""
log_info "Results: ${PASS} passed, ${FAIL} failed"

if [[ ${FAIL} -gt 0 ]]; then
  log_fail "❌ Smoke tests FAILED — ${FAIL} test(s) failed"
  exit 1
else
  log_success "✅ All smoke tests PASSED"
  exit 0
fi
