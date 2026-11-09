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
cv_step Given "a signed-in person with an existing note" $LINENO
signup "edit_${SUFFIX}@example.com"; T=$TOKEN
create_note "$T" "{\"title\":\"Old title $SUFFIX\",\"body\":\"Old body\"}"; NID=$NOTE_ID
OLD_UPDATED=$(jq -r .updated_at <<<"$CV_HTTP_BODY")
sleep 1.2   # timestamps have second resolution
NEW_TITLE="New title $SUFFIX"; NEW_BODY="New body $SUFFIX"

# When
cv_step When "they change the title and body of their note" $LINENO
cv_http PATCH "/notes/$NID" "{\"title\":\"$NEW_TITLE\",\"body\":\"$NEW_BODY\"}" -H "Authorization: Bearer $T"
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected 200 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO

# Then
cv_step Then "opening the note shows new values and a later last-changed time" $LINENO
cv_http GET "/notes/$NID" "" 200 -H "Authorization: Bearer $T"
[ "$(jq -r .title <<<"$CV_HTTP_BODY")" = "$NEW_TITLE" ] || cv_fail "expected title $NEW_TITLE got $CV_HTTP_BODY" $LINENO
[ "$(jq -r .body <<<"$CV_HTTP_BODY")" = "$NEW_BODY" ] || cv_fail "expected body $NEW_BODY got $CV_HTTP_BODY" $LINENO
NEW_UPDATED=$(jq -r .updated_at <<<"$CV_HTTP_BODY")
[[ "$NEW_UPDATED" > "$OLD_UPDATED" ]] || cv_fail "expected updated_at later than $OLD_UPDATED got $NEW_UPDATED" $LINENO

# Cleanup
cv_step Cleanup "delete the note" $LINENO
cv_http DELETE "/notes/$NID" "" -H "Authorization: Bearer $T" || true
echo "CODEVALID_TEST_ASSERTION_OK:api_25750298_5"
