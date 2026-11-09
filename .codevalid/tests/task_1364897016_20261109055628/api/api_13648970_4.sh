#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"

# Logs in and leaves status/body in CV_HTTP_*.
login() { cv_http POST /auth/login "$(jq -nc --arg e "$1" --arg p "$2" '{email:$e,password:$p}')"; }
register() { cv_http POST /auth/register "$(jq -nc --arg e "$1" --arg p "$2" '{email:$e,password:$p}')"; }

# Given
cv_step Given "a unique email and a valid password" $LINENO
EMAIL="reg4_${SUFFIX}@example.com"
PASS="ValidPass123"
login "$EMAIL" "$PASS"
[ "$CV_HTTP_STATUS" = "401" ] || cv_fail "expected no existing account got $CV_HTTP_STATUS" $LINENO

# When
cv_step When "register with empty email, then with empty password" $LINENO
register "" "$PASS"
S1="$CV_HTTP_STATUS"; B1="$CV_HTTP_BODY"
register "$EMAIL" ""
S2="$CV_HTTP_STATUS"; B2="$CV_HTTP_BODY"

# Then
cv_step Then "both are refused and no account exists" $LINENO
case "$S1" in 4??) ;; *) cv_fail "expected 4xx for empty email got $S1: $B1" $LINENO ;; esac
case "$S2" in 4??) ;; *) cv_fail "expected 4xx for empty password got $S2: $B2" $LINENO ;; esac
login "$EMAIL" "$PASS"
[ "$CV_HTTP_STATUS" = "401" ] && echo "$CV_HTTP_BODY" | grep -q "No account" || cv_fail "expected no account for $EMAIL got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO

# Cleanup
cv_step Cleanup "nothing was created" $LINENO
echo "nothing to clean"

echo "CODEVALID_TEST_ASSERTION_OK:api_13648970_4"
