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
  [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ] || cv_fail "expected access_token got none" $LINENO
}
# create_note TOKEN JSON; sets NOTE_ID
create_note() {
  cv_http POST /notes "$2" -H "Authorization: Bearer $1"
  [ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected create 201 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
  NOTE_ID=$(jq -r .id <<<"$CV_HTTP_BODY")
}

# Given
cv_step Given "person A owns a note and person B is signed in" $LINENO
signup "editA_${SUFFIX}@example.com"; TA=$TOKEN
signup "editB_${SUFFIX}@example.com"; TB=$TOKEN
A_TITLE="A title $SUFFIX"; A_BODY="A body $SUFFIX"
create_note "$TA" "{\"title\":\"$A_TITLE\",\"body\":\"$A_BODY\"}"; NID=$NOTE_ID
cv_http GET "/notes/$NID" "" 200 -H "Authorization: Bearer $TA"
BEFORE="$CV_HTTP_BODY"

# When
cv_step When "person B tries to change the title and body of A's note" $LINENO
cv_http PATCH "/notes/$NID" '{"title":"hijacked","body":"hijacked body"}' -H "Authorization: Bearer $TB"
S_EDIT="$CV_HTTP_STATUS"; B_EDIT="$CV_HTTP_BODY"

# Then
cv_step Then "B gets not found and A's note is unchanged" $LINENO
[ "$S_EDIT" = "404" ] || cv_fail "expected 404 for B editing A's note got $S_EDIT: $B_EDIT" $LINENO
if grep -q "$A_BODY" <<<"$B_EDIT"; then cv_fail "expected A's note content not exposed to B got $B_EDIT" $LINENO; fi
cv_http GET "/notes/$NID" "" 200 -H "Authorization: Bearer $TA"
[ "$(jq -r .title <<<"$CV_HTTP_BODY")" = "$A_TITLE" ] || cv_fail "expected title '$A_TITLE' got $(jq -r .title <<<"$CV_HTTP_BODY")" $LINENO
[ "$(jq -r .body <<<"$CV_HTTP_BODY")" = "$A_BODY" ] || cv_fail "expected body '$A_BODY' got $(jq -r .body <<<"$CV_HTTP_BODY")" $LINENO
[ "$(jq -r .updated_at <<<"$CV_HTTP_BODY")" = "$(jq -r .updated_at <<<"$BEFORE")" ] || cv_fail "expected updated_at unchanged got $CV_HTTP_BODY vs $BEFORE" $LINENO

# Cleanup
cv_step Cleanup "A deletes the note" $LINENO
cv_http DELETE "/notes/$NID" "" -H "Authorization: Bearer $TA" || true
echo "CODEVALID_TEST_ASSERTION_OK:api_25750298_17"
