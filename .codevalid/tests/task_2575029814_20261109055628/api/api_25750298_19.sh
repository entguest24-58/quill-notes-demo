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
cv_step Given "person A owns an unpinned note and person B is signed in" $LINENO
signup "pinA_${SUFFIX}@example.com"; TA=$TOKEN
signup "pinB_${SUFFIX}@example.com"; TB=$TOKEN
create_note "$TA" "{\"title\":\"Pin target $SUFFIX\",\"body\":\"b\",\"pinned\":false}"; NID=$NOTE_ID
cv_http GET "/notes/$NID" "" 200 -H "Authorization: Bearer $TA"
BEFORE="$CV_HTTP_BODY"
[ "$(jq -r .pinned <<<"$BEFORE")" = "false" ] || cv_fail "expected note to start unpinned got $BEFORE" $LINENO

# When
cv_step When "person B tries to pin A's note" $LINENO
cv_http PATCH "/notes/$NID" '{"pinned":true}' -H "Authorization: Bearer $TB"
S_PIN="$CV_HTTP_STATUS"; B_PIN="$CV_HTTP_BODY"

# Then
cv_step Then "A's note keeps its pinned state and B gets nothing back" $LINENO
cv_http GET "/notes/$NID" "" 200 -H "Authorization: Bearer $TA"
[ "$(jq -r .pinned <<<"$CV_HTTP_BODY")" = "false" ] || cv_fail "expected A's note to stay unpinned after B's attempt (B got $S_PIN) got $CV_HTTP_BODY" $LINENO
[ "$(jq -r .updated_at <<<"$CV_HTTP_BODY")" = "$(jq -r .updated_at <<<"$BEFORE")" ] || cv_fail "expected updated_at unchanged got $CV_HTTP_BODY" $LINENO
case "$S_PIN" in 2*) cv_fail "expected B's pin attempt refused got $S_PIN: $B_PIN" $LINENO ;; esac
cv_http GET "/notes?pinned=true" "" 200 -H "Authorization: Bearer $TA"
jq -e --argjson id "$NID" 'any(.[]; .id==$id) | not' <<<"$CV_HTTP_BODY" >/dev/null || cv_fail "expected note $NID absent from A's pinned list got $CV_HTTP_BODY" $LINENO

# Cleanup
cv_step Cleanup "A deletes the note" $LINENO
cv_http DELETE "/notes/$NID" "" -H "Authorization: Bearer $TA" || true
echo "CODEVALID_TEST_ASSERTION_OK:api_25750298_19"
