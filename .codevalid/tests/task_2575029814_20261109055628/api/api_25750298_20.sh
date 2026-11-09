#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
PASSWORD="Passw0rd!${SUFFIX: -6}"

# register + login; sets USER_ID, TOKEN
signup() {
  local email="$1"
  cv_http POST /auth/register "{\"email\":\"$email\",\"password\":\"$PASSWORD\"}"
  [ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected register 201 got $CV_HTTP_STATUS" $LINENO
  USER_ID=$(jq -r .id <<<"$CV_HTTP_BODY")
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
cv_step Given "persons A and B are signed in and B owns a note" $LINENO
signup "ownA_${SUFFIX}@example.com"; TA=$TOKEN; A_ID=$USER_ID
signup "ownB_${SUFFIX}@example.com"; TB=$TOKEN
create_note "$TB" "{\"title\":\"B own $SUFFIX\",\"body\":\"b\"}"; B_NID=$NOTE_ID

# When
cv_step When "B creates a note and edits their note while supplying A as owner" $LINENO
cv_http POST /notes "{\"title\":\"Forged $SUFFIX\",\"body\":\"f\",\"owner_id\":$A_ID,\"owner\":$A_ID,\"user_id\":$A_ID}" -H "Authorization: Bearer $TB"
S_CREATE="$CV_HTTP_STATUS"; FORGED_ID=$(jq -r '.id // empty' <<<"$CV_HTTP_BODY" 2>/dev/null || true)
cv_http PATCH "/notes/$B_NID" "{\"title\":\"B edited $SUFFIX\",\"owner_id\":$A_ID,\"owner\":$A_ID,\"user_id\":$A_ID}" -H "Authorization: Bearer $TB"
S_EDIT="$CV_HTTP_STATUS"

# Then
cv_step Then "both notes stay owned by B and never appear in A's list" $LINENO
echo "create status=$S_CREATE edit status=$S_EDIT"
cv_http GET /notes "" 200 -H "Authorization: Bearer $TA"
if grep -q "$SUFFIX" <<<"$CV_HTTP_BODY"; then cv_fail "expected none of B's notes in A's list got $CV_HTTP_BODY" $LINENO; fi
cv_http GET "/notes/$B_NID" "" -H "Authorization: Bearer $TA"
[ "$CV_HTTP_STATUS" = "404" ] || cv_fail "expected A cannot open B's edited note (404) got $CV_HTTP_STATUS" $LINENO
cv_http GET "/notes/$B_NID" "" 200 -H "Authorization: Bearer $TB"
if [ -n "$FORGED_ID" ]; then
  cv_http GET "/notes/$FORGED_ID" "" -H "Authorization: Bearer $TA"
  [ "$CV_HTTP_STATUS" = "404" ] || cv_fail "expected A cannot open forged note (404) got $CV_HTTP_STATUS" $LINENO
  cv_http GET "/notes/$FORGED_ID" "" -H "Authorization: Bearer $TB"
  [ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected forged note still owned by B (200) got $CV_HTTP_STATUS" $LINENO
fi

# Cleanup
cv_step Cleanup "B deletes the notes" $LINENO
cv_http DELETE "/notes/$B_NID" "" -H "Authorization: Bearer $TB" || true
if [ -n "$FORGED_ID" ]; then cv_http DELETE "/notes/$FORGED_ID" "" -H "Authorization: Bearer $TB" || true; fi
echo "CODEVALID_TEST_ASSERTION_OK:api_25750298_20"
