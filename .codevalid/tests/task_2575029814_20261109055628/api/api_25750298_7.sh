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
cv_step Given "a signed-in person with a note" $LINENO
signup "noop_${SUFFIX}@example.com"; T=$TOKEN
TITLE="Same $SUFFIX"; BODY="Same body $SUFFIX"
create_note "$T" "{\"title\":\"$TITLE\",\"body\":\"$BODY\",\"pinned\":false}"; NID=$NOTE_ID
cv_http GET "/notes/$NID" "" 200 -H "Authorization: Bearer $T"
BEFORE="$CV_HTTP_BODY"
sleep 1.5

# When
cv_step When "they submit an edit with the same title, body and pinned state" $LINENO
cv_http PATCH "/notes/$NID" "{\"title\":\"$TITLE\",\"body\":\"$BODY\",\"pinned\":false}" -H "Authorization: Bearer $T"
ST=$CV_HTTP_STATUS

# Then
cv_step Then "the edit is refused and the note and its last-changed time are unchanged" $LINENO
cv_http GET "/notes/$NID" "" 200 -H "Authorization: Bearer $T"
AFTER="$CV_HTTP_BODY"
[ "${ST:0:1}" = "4" ] || cv_fail "expected no-op edit refused (4xx) got $ST" $LINENO
[ "$(jq -r .updated_at <<<"$AFTER")" = "$(jq -r .updated_at <<<"$BEFORE")" ] || cv_fail "expected updated_at unchanged $(jq -r .updated_at <<<"$BEFORE") got $(jq -r .updated_at <<<"$AFTER")" $LINENO
jq -e --argjson b "$BEFORE" '. == $b' <<<"$AFTER" >/dev/null || cv_fail "expected note unchanged $BEFORE got $AFTER" $LINENO

# Cleanup
cv_step Cleanup "delete the note" $LINENO
cv_http DELETE "/notes/$NID" "" -H "Authorization: Bearer $T" || true
echo "CODEVALID_TEST_ASSERTION_OK:api_25750298_7"
