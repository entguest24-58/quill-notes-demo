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
cv_step Given "a person registered with a lowercase email and one note" $LINENO
LOCAL="user${SUFFIX}"
EMAIL="${LOCAL}@example.com"
MIXED="$(printf '%s' "$LOCAL" | tr '[:lower:]' '[:upper:]')@Example.COM"
register_and_login "$EMAIL"
SETUP_TOKEN="$TOKEN"
create_note "$SETUP_TOKEN" "note-$SUFFIX"

# When
cv_step When "sign in using the email in different case" $LINENO
cv_http POST /auth/login "{\"email\":\"$MIXED\",\"password\":\"$PASSWORD\"}"
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected 200 signing in as $MIXED got $CV_HTTP_STATUS" $LINENO
TOKEN2=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.access_token // empty')
[ -n "$TOKEN2" ] || cv_fail "expected access_token got none" $LINENO

# Then
cv_step Then "the token reaches the same account's notes" $LINENO
cv_http GET /notes "" -H "Authorization: Bearer $TOKEN2"
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected 200 listing notes got $CV_HTTP_STATUS" $LINENO
printf '%s' "$CV_HTTP_BODY" | jq -e --argjson id "$NOTE_ID" 'any(.[]; .id == $id)' >/dev/null \
  || cv_fail "expected note $NOTE_ID of $EMAIL in list got $CV_HTTP_BODY" $LINENO

# Cleanup
cv_step Cleanup "delete the created note" $LINENO
cv_http DELETE "/notes/$NOTE_ID" "" -H "Authorization: Bearer $SETUP_TOKEN"
echo "CODEVALID_TEST_ASSERTION_OK:api_98956333_2"
