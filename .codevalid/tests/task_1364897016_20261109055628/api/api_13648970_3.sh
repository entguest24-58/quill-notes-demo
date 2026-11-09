#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"

# Logs in and leaves status/body in CV_HTTP_*.
login() { cv_http POST /auth/login "$(jq -nc --arg e "$1" --arg p "$2" '{email:$e,password:$p}')"; }
register() { cv_http POST /auth/register "$(jq -nc --arg e "$1" --arg p "$2" '{email:$e,password:$p}')"; }

# Given
cv_step Given "malformed emails (no @, no domain) and a valid password" $LINENO
PASS="ValidPass123"
NOAT="reg3_${SUFFIX}example.com"
NODOMAIN="reg3_${SUFFIX}@"
# The well-formed counterpart must not exist yet
login "reg3_${SUFFIX}@example.com" "$PASS"
[ "$CV_HTTP_STATUS" = "401" ] || cv_fail "expected no existing account got $CV_HTTP_STATUS" $LINENO

# When
cv_step When "register with each malformed email" $LINENO
register "$NOAT" "$PASS"
S1="$CV_HTTP_STATUS"; B1="$CV_HTTP_BODY"
register "$NODOMAIN" "$PASS"
S2="$CV_HTTP_STATUS"; B2="$CV_HTTP_BODY"

# Then
cv_step Then "both registrations are refused and no account exists" $LINENO
case "$S1" in 4??) ;; *) cv_fail "expected 4xx for email without @ got $S1: $B1" $LINENO ;; esac
case "$S2" in 4??) ;; *) cv_fail "expected 4xx for email without domain got $S2: $B2" $LINENO ;; esac
login "$NOAT" "$PASS"
[ "$CV_HTTP_STATUS" != "200" ] || cv_fail "account was created for $NOAT" $LINENO
login "$NODOMAIN" "$PASS"
[ "$CV_HTTP_STATUS" != "200" ] || cv_fail "account was created for $NODOMAIN" $LINENO

# Cleanup
cv_step Cleanup "nothing was created" $LINENO
echo "nothing to clean"

echo "CODEVALID_TEST_ASSERTION_OK:api_13648970_3"
