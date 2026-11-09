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
cv_step Given "person B with a note and signed-in person A" $LINENO
register_and_login "signin7b_${SUFFIX}@example.com"
TOKEN_B="$TOKEN"
create_note "$TOKEN_B" "b-note-$SUFFIX"
B_NOTE="$NOTE_ID"
register_and_login "signin7a_${SUFFIX}@example.com"
TOKEN_A="$TOKEN"

# When
cv_step When "A tries to read, list and change B's note" $LINENO
cv_http GET "/notes/$B_NOTE" "" -H "Authorization: Bearer $TOKEN_A"; S_GET="$CV_HTTP_STATUS"; B_GET="$CV_HTTP_BODY"
cv_http GET /notes "" -H "Authorization: Bearer $TOKEN_A"; B_LIST="$CV_HTTP_BODY"
cv_http PATCH "/notes/$B_NOTE" '{"title":"hijacked"}' -H "Authorization: Bearer $TOKEN_A"; S_PATCH="$CV_HTTP_STATUS"

# Then
cv_step Then "B's note not exposed to A and unchanged when B reads it" $LINENO
[ "$S_GET" -ge 400 ] || cv_fail "expected refusal reading B's note got $S_GET" $LINENO
printf '%s%s' "$B_GET" "$B_LIST" | grep -q "b-note-$SUFFIX" && cv_fail "expected B's note hidden from A got exposed" $LINENO
[ "$S_PATCH" -ge 400 ] || cv_fail "expected refusal changing B's note got $S_PATCH" $LINENO
cv_http GET "/notes/$B_NOTE" "" -H "Authorization: Bearer $TOKEN_B"
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected B to read note got $CV_HTTP_STATUS" $LINENO
T=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.title')
[ "$T" = "b-note-$SUFFIX" ] || cv_fail "expected B's note title unchanged got $T" $LINENO

# Cleanup
cv_step Cleanup "delete B's note" $LINENO
cv_http DELETE "/notes/$B_NOTE" "" -H "Authorization: Bearer $TOKEN_B"
echo "CODEVALID_TEST_ASSERTION_OK:api_98956333_7"
