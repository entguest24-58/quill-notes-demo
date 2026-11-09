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
signup "create_${SUFFIX}@example.com"; T=$TOKEN
TITLE="Groceries $SUFFIX"; BODY="Milk, eggs and bread $SUFFIX"

# When
cv_step When "they create a note with a valid title and body" $LINENO
cv_http POST /notes "{\"title\":\"$TITLE\",\"body\":\"$BODY\"}" -H "Authorization: Bearer $T"
[ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected 201 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
NID=$(jq -r .id <<<"$CV_HTTP_BODY")
[ -n "$NID" ] && [ "$NID" != "null" ] || cv_fail "expected note id in create response got $CV_HTTP_BODY" $LINENO

# Then
cv_step Then "the note opens with same title/body and is in their list" $LINENO
cv_http GET "/notes/$NID" "" 200 -H "Authorization: Bearer $T"
[ "$(jq -r .title <<<"$CV_HTTP_BODY")" = "$TITLE" ] || cv_fail "expected title $TITLE got $CV_HTTP_BODY" $LINENO
[ "$(jq -r .body <<<"$CV_HTTP_BODY")" = "$BODY" ] || cv_fail "expected body $BODY got $CV_HTTP_BODY" $LINENO
cv_http GET /notes "" 200 -H "Authorization: Bearer $T"
jq -e --argjson id "$NID" --arg t "$TITLE" 'any(.[]; .id==$id and .title==$t)' <<<"$CV_HTTP_BODY" >/dev/null   || cv_fail "expected note $NID in list got $CV_HTTP_BODY" $LINENO

# Cleanup
cv_step Cleanup "delete the created note" $LINENO
cv_http DELETE "/notes/$NID" "" -H "Authorization: Bearer $T" || true
echo "CODEVALID_TEST_ASSERTION_OK:api_25750298_1"
