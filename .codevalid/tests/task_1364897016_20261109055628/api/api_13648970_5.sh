#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"

# Logs in and leaves status/body in CV_HTTP_*.
login() { cv_http POST /auth/login "$(jq -nc --arg e "$1" --arg p "$2" '{email:$e,password:$p}')"; }
register() { cv_http POST /auth/register "$(jq -nc --arg e "$1" --arg p "$2" '{email:$e,password:$p}')"; }

# Given
cv_step Given "an existing account" $LINENO
EMAIL="reg5_${SUFFIX}@example.com"
PASS="OriginalPass123"
NEWPASS="DifferentPass456"
register "$EMAIL" "$PASS"
[ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected 201 creating account got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
ORIG_ID=$(echo "$CV_HTTP_BODY" | jq -r '.id')

# When
cv_step When "register again with the same email and a different password" $LINENO
register "$EMAIL" "$NEWPASS"
S="$CV_HTTP_STATUS"; B="$CV_HTTP_BODY"

# Then
cv_step Then "rejected; original password still works, new one does not" $LINENO
case "$S" in 4??) ;; *) cv_fail "expected 4xx for duplicate got $S: $B" $LINENO ;; esac
login "$EMAIL" "$PASS"
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected original password to still log in (200) got $CV_HTTP_STATUS" $LINENO
login "$EMAIL" "$NEWPASS"
[ "$CV_HTTP_STATUS" = "401" ] || cv_fail "expected new password to be refused (401) got $CV_HTTP_STATUS" $LINENO

# Cleanup
cv_step Cleanup "no user-delete endpoint exists; unique email leaves no conflict" $LINENO
echo "user $EMAIL left in place (no delete route)"

echo "CODEVALID_TEST_ASSERTION_OK:api_13648970_5"
