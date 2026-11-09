#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
# JWT_SECRET from .codevalid/docker-compose.yml (app service)
JWT_SECRET="${JWT_SECRET:-codevalid-test-secret}"
SUFFIX="$(date +%s%N)"
PASSWORD="Passw0rd-${SUFFIX}"

register_and_login() { # $1=email -> sets USER_ID, TOKEN
  cv_http POST /auth/register "{\"email\":\"$1\",\"password\":\"$PASSWORD\"}"
  [ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected 201 registering $1 got $CV_HTTP_STATUS" $LINENO
  USER_ID=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.id')
  cv_http POST /auth/login "{\"email\":\"$1\",\"password\":\"$PASSWORD\"}"
  [ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected 200 logging in $1 got $CV_HTTP_STATUS" $LINENO
  TOKEN=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.access_token // empty')
  [ -n "$TOKEN" ] || cv_fail "expected access_token from login got none" $LINENO
}

create_note() { # $1=token $2=title -> sets NOTE_ID
  cv_http POST /notes "{\"title\":\"$2\",\"body\":\"body-$SUFFIX\"}" -H "Authorization: Bearer $1"
  [ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected 201 creating note got $CV_HTTP_STATUS" $LINENO
  NOTE_ID=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.id')
}

# Given
cv_step Given "a registered person and an unregistered email" $LINENO
EMAIL="signin4_${SUFFIX}@example.com"
UNKNOWN="nobody4_${SUFFIX}@example.com"
cv_http POST /auth/register "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}"
[ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected 201 registering got $CV_HTTP_STATUS" $LINENO

# When
cv_step When "sign in with a wrong password, then with an unknown email" $LINENO
cv_http POST /auth/login "{\"email\":\"$EMAIL\",\"password\":\"WrongPass-${SUFFIX}\"}"
S1="$CV_HTTP_STATUS"; B1="$CV_HTTP_BODY"
cv_http POST /auth/login "{\"email\":\"$UNKNOWN\",\"password\":\"$PASSWORD\"}"
S2="$CV_HTTP_STATUS"; B2="$CV_HTTP_BODY"

# Then
cv_step Then "both refused with no token and identical responses" $LINENO
[ "$S1" -ge 400 ] && [ "$S1" -lt 500 ] || cv_fail "expected 4xx refusal for wrong password got $S1" $LINENO
[ "$S2" -ge 400 ] && [ "$S2" -lt 500 ] || cv_fail "expected 4xx refusal for unknown email got $S2" $LINENO
printf '%s' "$B1" | grep -q access_token && cv_fail "expected no token for wrong password got $B1" $LINENO
printf '%s' "$B2" | grep -q access_token && cv_fail "expected no token for unknown email got $B2" $LINENO
[ "$S1" = "$S2" ] || cv_fail "expected same status for both got wrong-password=$S1 unknown-email=$S2" $LINENO
[ "$B1" = "$B2" ] || cv_fail "expected identical refusal bodies, got wrong-password=$B1 unknown-email=$B2 (reveals which credential was wrong)" $LINENO

# Cleanup
cv_step Cleanup "nothing to remove (no API to delete users)" $LINENO
echo "CODEVALID_TEST_ASSERTION_OK:api_98956333_4"
