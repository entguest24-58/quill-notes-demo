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
cv_step Given "a registered person with one note" $LINENO
EMAIL="signin1_${SUFFIX}@example.com"
cv_http POST /auth/register "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}"
[ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected 201 registering got $CV_HTTP_STATUS" $LINENO
cv_prereq "obtain setup token to seed a note" $LINENO
cv_http POST /auth/login "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}"
SETUP_TOKEN=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.access_token // empty')
[ -n "$SETUP_TOKEN" ] || cv_fail "expected setup token got status $CV_HTTP_STATUS" $LINENO
create_note "$SETUP_TOKEN" "note-$SUFFIX"

# When
cv_step When "sign in with the correct email and password" $LINENO
cv_http POST /auth/login "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}"
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected 200 on sign-in got $CV_HTTP_STATUS" $LINENO
TOKEN=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.access_token // empty')
[ -n "$TOKEN" ] || cv_fail "expected access_token in sign-in response got none" $LINENO

# Then
cv_step Then "the returned token gives access to the person's notes" $LINENO
cv_http GET /notes "" -H "Authorization: Bearer $TOKEN"
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected 200 listing notes got $CV_HTTP_STATUS" $LINENO
printf '%s' "$CV_HTTP_BODY" | jq -e --argjson id "$NOTE_ID" 'any(.[]; .id == $id)' >/dev/null \
  || cv_fail "expected own note $NOTE_ID in notes list got $CV_HTTP_BODY" $LINENO
cv_http GET "/notes/$NOTE_ID" "" -H "Authorization: Bearer $TOKEN"
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected 200 reading own note got $CV_HTTP_STATUS" $LINENO

# Cleanup
cv_step Cleanup "delete the created note" $LINENO
cv_http DELETE "/notes/$NOTE_ID" "" -H "Authorization: Bearer $TOKEN"
echo "CODEVALID_TEST_ASSERTION_OK:api_98956333_1"
