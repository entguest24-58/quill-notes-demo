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
cv_step Given "a person with a note, plus a made-up and an altered token" $LINENO
EMAIL="signin6_${SUFFIX}@example.com"
register_and_login "$EMAIL"
create_note "$TOKEN" "note-$SUFFIX"
FAKE="not.a-real.token${SUFFIX}"
SIG=$(printf '%s' "$TOKEN" | cut -d. -f3)
LAST=${SIG: -2:1}; if [ "$LAST" = "A" ]; then NEW=B; else NEW=A; fi
ALTERED="$(printf '%s' "$TOKEN" | cut -d. -f1-2).${SIG:0:${#SIG}-2}${NEW}${SIG: -1}"

# When
cv_step When "attempt to read and change the note without a token and with bad tokens" $LINENO
cv_http GET /notes; S_LIST_NONE="$CV_HTTP_STATUS"; B_LIST_NONE="$CV_HTTP_BODY"
cv_http PATCH "/notes/$NOTE_ID" '{"title":"hacked-none"}'; S_PATCH_NONE="$CV_HTTP_STATUS"
cv_http GET /notes "" -H "Authorization: Bearer $FAKE"; S_LIST_FAKE="$CV_HTTP_STATUS"; B_LIST_FAKE="$CV_HTTP_BODY"
cv_http PATCH "/notes/$NOTE_ID" '{"title":"hacked-altered"}' -H "Authorization: Bearer $ALTERED"; S_PATCH_ALT="$CV_HTTP_STATUS"

# Then
cv_step Then "all attempts refused as unauthorized and the note is unchanged" $LINENO
[ "$S_LIST_NONE" = "401" ] || cv_fail "expected 401 listing without token got $S_LIST_NONE" $LINENO
[ "$S_PATCH_NONE" = "401" ] || cv_fail "expected 401 patching without token got $S_PATCH_NONE" $LINENO
[ "$S_LIST_FAKE" = "401" ] || cv_fail "expected 401 listing with made-up token got $S_LIST_FAKE" $LINENO
[ "$S_PATCH_ALT" = "401" ] || cv_fail "expected 401 patching with altered token got $S_PATCH_ALT" $LINENO
printf '%s%s' "$B_LIST_NONE" "$B_LIST_FAKE" | grep -q "note-$SUFFIX" && cv_fail "expected no notes returned to unauthenticated client" $LINENO
cv_http GET "/notes/$NOTE_ID" "" -H "Authorization: Bearer $TOKEN"
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected owner to read note got $CV_HTTP_STATUS" $LINENO
T=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.title')
[ "$T" = "note-$SUFFIX" ] || cv_fail "expected note title unchanged note-$SUFFIX got $T" $LINENO

# Cleanup
cv_step Cleanup "delete the created note" $LINENO
cv_http DELETE "/notes/$NOTE_ID" "" -H "Authorization: Bearer $TOKEN"
echo "CODEVALID_TEST_ASSERTION_OK:api_98956333_6"
