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
signup "editbad_${SUFFIX}@example.com"; T=$TOKEN
TITLE="Original $SUFFIX"; BODY="Original body $SUFFIX"
create_note "$T" "{\"title\":\"$TITLE\",\"body\":\"$BODY\",\"pinned\":false}"; NID=$NOTE_ID
T201=$(head -c 201 /dev/zero | tr '\0' 't')
B10001=$(head -c 10001 /dev/zero | tr '\0' 'b')

# When
cv_step When "they edit with an empty title, a 201-char title, and a 10,001-char body" $LINENO
cv_http PATCH "/notes/$NID" '{"title":""}' -H "Authorization: Bearer $T"; SE=$CV_HTTP_STATUS
cv_http PATCH "/notes/$NID" "{\"title\":\"$T201\"}" -H "Authorization: Bearer $T"; SL=$CV_HTTP_STATUS
cv_http PATCH "/notes/$NID" "{\"body\":\"$B10001\"}" -H "Authorization: Bearer $T"; SB=$CV_HTTP_STATUS

# Then
cv_step Then "each edit is refused and the note is unchanged" $LINENO
for s in "emptytitle:$SE" "longtitle:$SL" "longbody:$SB"; do
  st=${s#*:}
  [ "${st:0:1}" = "4" ] || cv_fail "expected ${s%%:*} edit refused (4xx) got $st" $LINENO
done
cv_http GET "/notes/$NID" "" 200 -H "Authorization: Bearer $T"
[ "$(jq -r .title <<<"$CV_HTTP_BODY")" = "$TITLE" ] || cv_fail "expected title unchanged got $CV_HTTP_BODY" $LINENO
[ "$(jq -r .body <<<"$CV_HTTP_BODY")" = "$BODY" ] || cv_fail "expected body unchanged got $(jq -r '.body|length' <<<"$CV_HTTP_BODY") chars" $LINENO

# Cleanup
cv_step Cleanup "delete the note" $LINENO
cv_http DELETE "/notes/$NID" "" -H "Authorization: Bearer $T" || true
echo "CODEVALID_TEST_ASSERTION_OK:api_25750298_6"
