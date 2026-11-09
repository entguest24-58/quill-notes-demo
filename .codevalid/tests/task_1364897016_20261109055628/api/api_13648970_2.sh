#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"

# Logs in and leaves status/body in CV_HTTP_*.
login() { cv_http POST /auth/login "$(jq -nc --arg e "$1" --arg p "$2" '{email:$e,password:$p}')"; }
register() { cv_http POST /auth/register "$(jq -nc --arg e "$1" --arg p "$2" '{email:$e,password:$p}')"; }

# Given
cv_step Given "an unused email and 7- and 8-character passwords" $LINENO
EMAIL="reg2_${SUFFIX}@example.com"
PASS7="Abcdef1"
PASS8="Abcdef12"
[ ${#PASS7} -eq 7 ] && [ ${#PASS8} -eq 8 ] || cv_fail "test data lengths wrong" $LINENO
login "$EMAIL" "$PASS8"
[ "$CV_HTTP_STATUS" = "401" ] || cv_fail "expected no existing account (401) got $CV_HTTP_STATUS" $LINENO

# When
cv_step When "register with a 7-character password, then with an 8-character password" $LINENO
register "$EMAIL" "$PASS7"
S7="$CV_HTTP_STATUS"; B7="$CV_HTTP_BODY"
login "$EMAIL" "$PASS8"  # login validates length too, so probe existence with a valid-length password
L7="$CV_HTTP_STATUS"; L7B="$CV_HTTP_BODY"
register "$EMAIL" "$PASS8"
S8="$CV_HTTP_STATUS"; B8="$CV_HTTP_BODY"

# Then
cv_step Then "7 chars refused with no account, 8 chars accepted" $LINENO
case "$S7" in 4??) ;; *) cv_fail "expected 4xx for 7-char password got $S7: $B7" $LINENO ;; esac
[ "$S7" != "409" ] || cv_fail "7-char refusal should be validation, got 409 (account existed?)" $LINENO
[ "$L7" = "401" ] && echo "$L7B" | grep -q "No account" || cv_fail "expected no account after refused 7-char registration got $L7: $L7B" $LINENO
[ "$S8" = "201" ] || cv_fail "expected 201 for 8-char password got $S8: $B8" $LINENO
login "$EMAIL" "$PASS8"
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected login 200 with 8-char password got $CV_HTTP_STATUS" $LINENO

# Cleanup
cv_step Cleanup "no user-delete endpoint exists; unique email leaves no conflict" $LINENO
echo "user $EMAIL left in place (no delete route)"

echo "CODEVALID_TEST_ASSERTION_OK:api_13648970_2"
