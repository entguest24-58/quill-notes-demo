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
cv_step Given "person A with a note and a separate person B" $LINENO
signup "owna_${SUFFIX}@example.com"; TA=$TOKEN
TITLE="A private $SUFFIX"; BODY="A secret body $SUFFIX"
create_note "$TA" "{\"title\":\"$TITLE\",\"body\":\"$BODY\"}"; NID=$NOTE_ID
signup "othb_${SUFFIX}@example.com"; TB=$TOKEN

# When
cv_step When "person B opens A's note" $LINENO
cv_http GET "/notes/$NID" "" -H "Authorization: Bearer $TB"

# Then
cv_step Then "the result is not found and none of A's content is returned" $LINENO
[ "$CV_HTTP_STATUS" = "404" ] || cv_fail "expected 404 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
if grep -q "$SUFFIX" <<<"$CV_HTTP_BODY"; then cv_fail "expected none of A's content got $CV_HTTP_BODY" $LINENO; fi
cv_http GET "/notes/$NID" "" 200 -H "Authorization: Bearer $TA"
[ "$(jq -r .title <<<"$CV_HTTP_BODY")" = "$TITLE" ] || cv_fail "expected A's note intact got $CV_HTTP_BODY" $LINENO

# Cleanup
cv_step Cleanup "delete A's note" $LINENO
cv_http DELETE "/notes/$NID" "" -H "Authorization: Bearer $TA" || true
echo "CODEVALID_TEST_ASSERTION_OK:api_25750298_16"
