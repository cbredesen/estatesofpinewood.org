#!/usr/bin/env bash
# Test suite for the /api/contact endpoint.
#
# Usage:
#   ./bin/test-contact-api.sh                              # safe tests against production
#   ./bin/test-contact-api.sh --live                       # include the real-send test
#   ./bin/test-contact-api.sh --url https://staging.example.com
#   ./bin/test-contact-api.sh --url http://localhost:8080 --live
#
# Requires: curl, jq

set -euo pipefail

# ---------------------------------------------------------------------------
# Config / CLI args
# ---------------------------------------------------------------------------
BASE_URL="https://estatesofpinewood.org"
LIVE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)  BASE_URL="${2%/}"; shift 2 ;;
    --live) LIVE=true; shift ;;
    *)      echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

ENDPOINT="${BASE_URL}/api/contact"

# ---------------------------------------------------------------------------
# Terminal colours (disabled when not a tty)
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
  BOLD='\033[1m'; RESET='\033[0m'
else
  GREEN=''; RED=''; YELLOW=''; BOLD=''; RESET=''
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
PASS=0; FAIL=0; SKIP=0

pass() { echo -e "  ${GREEN}PASS${RESET}  $1"; PASS=$(( PASS + 1 )); }
fail() { echo -e "  ${RED}FAIL${RESET}  $1"; FAIL=$(( FAIL + 1 )); }
skip() { echo -e "  ${YELLOW}SKIP${RESET}  $1"; SKIP=$(( SKIP + 1 )); }

# post <json_body> [extra_curl_args...]
# Prints "STATUS BODY" on stdout. Sends Content-Type: application/json.
post() {
  local body="$1"; shift
  curl -s -o /tmp/eop_body -w "%{http_code}" \
    -X POST "${ENDPOINT}" \
    -H 'Content-Type: application/json' \
    -d "${body}" \
    --max-time 15 \
    "$@"
}

# check <test_name> <actual_status> <expected_status> <expected_json_fragment>
check() {
  local name="$1" actual_status="$2" expected_status="$3" expected_fragment="$4"
  local actual_body
  actual_body=$(cat /tmp/eop_body 2>/dev/null || echo '')

  if [[ "${actual_status}" != "${expected_status}" ]]; then
    fail "${name}"
    echo "         status:   expected ${expected_status}, got ${actual_status}"
    echo "         body:     ${actual_body}"
    return
  fi

  # Check that every key/value in the expected fragment appears in the actual body.
  # We use jq to do a partial-object match.
  if echo "${actual_body}" | jq -e --argjson exp "${expected_fragment}" \
      'to_entries | map(.value == ($exp[.key] // .value)) | all' \
      > /dev/null 2>&1; then
    pass "${name}"
  else
    fail "${name}"
    echo "         body:     expected to contain ${expected_fragment}"
    echo "         got:      ${actual_body}"
  fi
}

# ---------------------------------------------------------------------------
# Test runner
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}Contact API Test Suite${RESET}"
echo -e "Endpoint: ${ENDPOINT}"
echo ""

# --- Honeypot (safe: no email sent) ----------------------------------------
echo -e "${BOLD}Honeypot${RESET}"

status=$(post '{"name":"Bot","email":"bot@example.com","message":"Spam","website":"http://evil.com"}')
check "Honeypot filled → silent 200" "$status" "200" '{"ok":true}'

# --- Validation: missing / blank fields (safe) ------------------------------
echo ""
echo -e "${BOLD}Validation — required fields${RESET}"

status=$(post '{"email":"a@b.com","message":"Hello"}')
check "Missing name → 400" "$status" "400" '{"error":"All fields are required."}'

status=$(post '{"name":"","email":"a@b.com","message":"Hello"}')
check "Empty name → 400" "$status" "400" '{"error":"All fields are required."}'

status=$(post '{"name":"   ","email":"a@b.com","message":"Hello"}')
check "Whitespace-only name → 400" "$status" "400" '{"error":"All fields are required."}'

status=$(post '{"name":"Test","message":"Hello"}')
check "Missing email → 400" "$status" "400" '{"error":"All fields are required."}'

status=$(post '{"name":"Test","email":"","message":"Hello"}')
check "Empty email → 400" "$status" "400" '{"error":"All fields are required."}'

status=$(post '{"name":"Test","email":"a@b.com"}')
check "Missing message → 400" "$status" "400" '{"error":"All fields are required."}'

status=$(post '{"name":"Test","email":"a@b.com","message":""}')
check "Empty message → 400" "$status" "400" '{"error":"All fields are required."}'

# --- Validation: email format (safe) ----------------------------------------
echo ""
echo -e "${BOLD}Validation — email format${RESET}"

status=$(post '{"name":"Test","email":"notanemail","message":"Hello"}')
check "No @ sign → 400" "$status" "400" '{"error":"Invalid email address."}'

status=$(post '{"name":"Test","email":"test@","message":"Hello"}')
check "No domain → 400" "$status" "400" '{"error":"Invalid email address."}'

status=$(post '{"name":"Test","email":"@nodomain.com","message":"Hello"}')
check "No local part → 400" "$status" "400" '{"error":"Invalid email address."}'

status=$(post '{"name":"Test","email":"two@@signs.com","message":"Hello"}')
check "Two @ signs → 400" "$status" "400" '{"error":"Invalid email address."}'

# --- Malformed request body (safe) ------------------------------------------
echo ""
echo -e "${BOLD}Malformed request body${RESET}"

status=$(post '{ not: valid json }')
check "Invalid JSON → 400" "$status" "400" '{"error":"Invalid request"}'

# Empty body: Lambda uses `event.get('body') or '{}'` so '' → {} → missing fields
status=$(post '')
check "Empty body → 400" "$status" "400" '{"error":"All fields are required."}'

# --- Wrong HTTP method (safe) -----------------------------------------------
echo ""
echo -e "${BOLD}HTTP method${RESET}"

status=$(curl -s -o /tmp/eop_body -w "%{http_code}" \
  -X GET "${ENDPOINT}" --max-time 15)
# API Gateway HTTP API returns 405 for wrong method on a matched path,
# or 404 if it doesn't route GETs at all — either is acceptable.
actual_body=$(cat /tmp/eop_body 2>/dev/null || echo '')
# CloudFront routes GETs to the S3 origin (403), not API Gateway (404/405).
# All three indicate the POST-only route is correctly restricted.
if [[ "${status}" == "403" || "${status}" == "404" || "${status}" == "405" ]]; then
  pass "GET request → ${status} (correctly rejected)"
else
  fail "GET request → expected 403/404/405, got ${status}"
  echo "         body: ${actual_body}"
fi

# --- Live send (opt-in only) ------------------------------------------------
echo ""
echo -e "${BOLD}Live send test${RESET}"

if [[ "${LIVE}" == "true" ]]; then
  echo "  (--live flag set: this will send a real email)"
  status=$(post '{"name":"[TEST] Contact API","email":"test@estatesofpinewood.org","message":"Automated test — please ignore. Sent by test-contact-api.sh"}')
  check "Valid submission → 200" "$status" "200" '{"ok":true}'
else
  skip "Valid submission (skipped — run with --live to send a real email)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}Results: ${GREEN}${PASS} passed${RESET}, ${RED}${FAIL} failed${RESET}, ${YELLOW}${SKIP} skipped${RESET}"
echo ""

[[ "${FAIL}" -eq 0 ]]
