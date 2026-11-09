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
cv_step Given "person A with notes matching by title, by body, and not at all; person B with a matching note" $LINENO
WORD="zebra${SUFFIX: -8}"
signup "searchb_${SUFFIX}@example.com"; TB=$TOKEN
create_note "$TB" "{\"title\":\"B $WORD title\",\"body\":\"B body $WORD\"}"; BN=$NOTE_ID
signup "searcha_${SUFFIX}@example.com"; TA=$TOKEN
create_note "$TA" "{\"title\":\"Trip $WORD plans\",\"body\":\"pack bags\"}"; N_TITLE=$NOTE_ID
create_note "$TA" "{\"title\":\"Shopping\",\"body\":\"buy a $WORD toy\"}"; N_BODY=$NOTE_ID
create_note "$TA" "{\"title\":\"Unrelated\",\"body\":\"nothing here\"}"; N_NONE=$NOTE_ID

# When
cv_step When "A searches their list for the word" $LINENO
cv_http GET "/notes?q=$WORD" "" -H "Authorization: Bearer $TA"
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected 200 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO

# Then
cv_step Then "title and body matches are returned; non-matching and other people's notes are not" $LINENO
GOT=$(jq -c '[.[].id] | sort' <<<"$CV_HTTP_BODY")
jq -e --argjson id "$N_TITLE" 'any(.[]; .id==$id)' <<<"$CV_HTTP_BODY" >/dev/null || cv_fail "expected title match $N_TITLE in results got $GOT" $LINENO
jq -e --argjson id "$N_BODY" 'any(.[]; .id==$id)' <<<"$CV_HTTP_BODY" >/dev/null || cv_fail "expected body match $N_BODY in results got $GOT" $LINENO
jq -e --argjson id "$N_NONE" 'any(.[]; .id==$id) | not' <<<"$CV_HTTP_BODY" >/dev/null || cv_fail "expected non-matching note $N_NONE absent got $GOT" $LINENO
jq -e --argjson id "$BN" 'any(.[]; .id==$id) | not' <<<"$CV_HTTP_BODY" >/dev/null || cv_fail "expected B's note $BN absent got $GOT" $LINENO
[ "$(jq length <<<"$CV_HTTP_BODY")" = "2" ] || cv_fail "expected exactly 2 results got $GOT" $LINENO

# Cleanup
cv_step Cleanup "delete created notes" $LINENO
for n in $N_TITLE $N_BODY $N_NONE; do cv_http DELETE "/notes/$n" "" -H "Authorization: Bearer $TA" || true; done
cv_http DELETE "/notes/$BN" "" -H "Authorization: Bearer $TB" || true
echo "CODEVALID_TEST_ASSERTION_OK:api_25750298_14"
