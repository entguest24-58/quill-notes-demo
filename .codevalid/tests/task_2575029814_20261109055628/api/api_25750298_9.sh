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
cv_step Given "a signed-in person with their own note" $LINENO
signup "del_${SUFFIX}@example.com"; T=$TOKEN
create_note "$T" "{\"title\":\"Delete me $SUFFIX\",\"body\":\"x\"}"; NID=$NOTE_ID

# When
cv_step When "they delete the note" $LINENO
cv_http DELETE "/notes/$NID" "" -H "Authorization: Bearer $T"
[ "$CV_HTTP_STATUS" = "204" ] || [ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected 2xx got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO

# Then
cv_step Then "the note is gone from the list and opening it returns 404" $LINENO
cv_http GET /notes "" 200 -H "Authorization: Bearer $T"
jq -e --argjson id "$NID" 'any(.[]; .id==$id) | not' <<<"$CV_HTTP_BODY" >/dev/null || cv_fail "expected note $NID absent from list got $CV_HTTP_BODY" $LINENO
cv_http GET "/notes/$NID" "" -H "Authorization: Bearer $T"
[ "$CV_HTTP_STATUS" = "404" ] || cv_fail "expected 404 opening deleted note got $CV_HTTP_STATUS" $LINENO

# Cleanup
cv_step Cleanup "nothing left to remove (note already deleted)" $LINENO
echo "CODEVALID_TEST_ASSERTION_OK:api_25750298_9"
