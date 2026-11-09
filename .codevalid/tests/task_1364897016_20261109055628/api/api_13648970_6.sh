#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"

# Logs in and leaves status/body in CV_HTTP_*.
login() { cv_http POST /auth/login "$(jq -nc --arg e "$1" --arg p "$2" '{email:$e,password:$p}')"; }
register() { cv_http POST /auth/register "$(jq -nc --arg e "$1" --arg p "$2" '{email:$e,password:$p}')"; }

# Given
cv_step Given "an account registered with a lowercase email" $LINENO
LOWER="user_${SUFFIX}@example.com"
MIXED="User_${SUFFIX}@Example.COM"
PASS="OriginalPass123"
NEWPASS="DifferentPass456"
register "$LOWER" "$PASS"
[ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected 201 creating account got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO

# When
cv_step When "register with the same email in different letter case" $LINENO
register "$MIXED" "$NEWPASS"
S="$CV_HTTP_STATUS"; B="$CV_HTTP_BODY"

# Then
cv_step Then "rejected as duplicate and existing account unchanged" $LINENO
case "$S" in 4??) ;; *) cv_fail "expected 4xx for case-variant duplicate got $S: $B" $LINENO ;; esac
login "$LOWER" "$PASS"
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected original password to log in (200) got $CV_HTTP_STATUS" $LINENO
login "$MIXED" "$NEWPASS"
[ "$CV_HTTP_STATUS" = "401" ] || cv_fail "expected new password refused for case variant (401) got $CV_HTTP_STATUS" $LINENO
login "$MIXED" "$PASS"
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected case-variant email to log into same account (200) got $CV_HTTP_STATUS" $LINENO

# Cleanup
cv_step Cleanup "no user-delete endpoint exists; unique email leaves no conflict" $LINENO
echo "user $LOWER left in place (no delete route)"

echo "CODEVALID_TEST_ASSERTION_OK:api_13648970_6"
