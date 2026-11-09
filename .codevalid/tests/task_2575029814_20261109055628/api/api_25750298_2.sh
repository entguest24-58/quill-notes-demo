#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
PASSWORD="Passw0rd!${SUFFIX: -6}"

# register + login; sets TOKEN
signup() {
  local email="$1"
  cv_http POST /auth/register "{\"email\":\"$email\",\"password\":\"$PASSWORD\"}"
  [ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected register 201 got $CV_HTTP_STATUS" $LINENO
  cv_http POST /auth/login "{\"email\":\"$email\",\"password\":\"$PASSWORD\"}"
  [ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected login 200 got $CV_HTTP_STATUS" $LINENO
  TOKEN=$(jq -r .access_token <<<"$CV_HTTP_BODY")
}
# create_note TOKEN JSON; sets NOTE_ID
create_note() {
  cv_http POST /notes "$2" -H "Authorization: Bearer $1"
  [ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected create 201 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
  NOTE_ID=$(jq -r .id <<<"$CV_HTTP_BODY")
}

# Given
cv_step Given "a registered, signed-in person" $LINENO
signup "nobody_${SUFFIX}@example.com"; T=$TOKEN
TITLE="Title only $SUFFIX"

# When
cv_step When "they create a note with only a title" $LINENO
cv_http POST /notes "{\"title\":\"$TITLE\"}" -H "Authorization: Bearer $T"
[ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected 201 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
NID=$(jq -r .id <<<"$CV_HTTP_BODY")
[ -n "$NID" ] && [ "$NID" != "null" ] || cv_fail "expected note id got $CV_HTTP_BODY" $LINENO

# Then
cv_step Then "the note opens with the title and an empty body" $LINENO
cv_http GET "/notes/$NID" "" 200 -H "Authorization: Bearer $T"
[ "$(jq -r .title <<<"$CV_HTTP_BODY")" = "$TITLE" ] || cv_fail "expected title $TITLE got $CV_HTTP_BODY" $LINENO
[ "$(jq -r '.body' <<<"$CV_HTTP_BODY")" = "" ] || cv_fail "expected empty body got $CV_HTTP_BODY" $LINENO

# Cleanup
cv_step Cleanup "delete the created note" $LINENO
cv_http DELETE "/notes/$NID" "" -H "Authorization: Bearer $T" || true
echo "CODEVALID_TEST_ASSERTION_OK:api_25750298_2"
