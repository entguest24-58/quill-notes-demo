#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"

# Logs in and leaves status/body in CV_HTTP_*.
login() { cv_http POST /auth/login "$(jq -nc --arg e "$1" --arg p "$2" '{email:$e,password:$p}')"; }
register() { cv_http POST /auth/register "$(jq -nc --arg e "$1" --arg p "$2" '{email:$e,password:$p}')"; }

# Given
cv_step Given "a fresh, unregistered email and a password longer than 8 characters" $LINENO
EMAIL="reg1_${SUFFIX}@example.com"
PASS="Sup3rSecretPass"
login "$EMAIL" "$PASS"
[ "$CV_HTTP_STATUS" = "401" ] || cv_fail "expected no existing account (401) got $CV_HTTP_STATUS" $LINENO

# When
cv_step When "register with the valid email and password" $LINENO
register "$EMAIL" "$PASS"
REG_STATUS="$CV_HTTP_STATUS"; REG_BODY="$CV_HTTP_BODY"

# Then
cv_step Then "registration is accepted and the account can log in" $LINENO
[ "$REG_STATUS" = "201" ] || cv_fail "expected 201 on register got $REG_STATUS: $REG_BODY" $LINENO
[ "$(echo "$REG_BODY" | jq -r '.email')" = "$EMAIL" ] || cv_fail "expected email $EMAIL in response got $REG_BODY" $LINENO
echo "$REG_BODY" | jq -e '.id | numbers' >/dev/null || cv_fail "expected numeric id got $REG_BODY" $LINENO
echo "$REG_BODY" | jq -e 'has("password") or has("password_hash") | not' >/dev/null || cv_fail "response leaks password data: $REG_BODY" $LINENO
login "$EMAIL" "$PASS"
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected login 200 for new account got $CV_HTTP_STATUS" $LINENO
TOKEN=$(echo "$CV_HTTP_BODY" | jq -r '.access_token // empty')
[ -n "$TOKEN" ] || cv_fail "expected access_token got $CV_HTTP_BODY" $LINENO
cv_http GET /notes 200 -H "Authorization: Bearer $TOKEN"

# Cleanup
cv_step Cleanup "no user-delete endpoint exists; unique email leaves no conflict" $LINENO
echo "user $EMAIL left in place (no delete route)"

echo "CODEVALID_TEST_ASSERTION_OK:api_13648970_1"
