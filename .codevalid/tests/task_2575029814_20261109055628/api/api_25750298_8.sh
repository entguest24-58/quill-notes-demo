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

ids_in_list() { jq -r '[.[].id] | map(tostring) | join(",")' <<<"$CV_HTTP_BODY"; }

# Given
cv_step Given "a signed-in person with three unpinned notes created in order A, B, C" $LINENO
signup "pin_${SUFFIX}@example.com"; T=$TOKEN
create_note "$T" '{"title":"Note A"}'; A=$NOTE_ID; sleep 1.2
create_note "$T" '{"title":"Note B"}'; B=$NOTE_ID; sleep 1.2
create_note "$T" '{"title":"Note C"}'; C=$NOTE_ID; sleep 1.2

# When
cv_step When "they pin the oldest note A" $LINENO
cv_http PATCH "/notes/$A" '{"pinned":true}' -H "Authorization: Bearer $T"
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected 200 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO

# Then
cv_step Then "A is listed first; after unpinning it is ordered by last-changed time" $LINENO
cv_http GET /notes "" 200 -H "Authorization: Bearer $T"
[ "$(jq -r '.[0].id' <<<"$CV_HTTP_BODY")" = "$A" ] || cv_fail "expected pinned note $A first got order $(ids_in_list)" $LINENO
[ "$(jq -r '.[0].pinned' <<<"$CV_HTTP_BODY")" = "true" ] || cv_fail "expected first note pinned=true got $CV_HTTP_BODY" $LINENO
sleep 1.2
cv_prereq "unpin note A (this change makes it the most recently changed)" $LINENO
cv_http PATCH "/notes/$A" '{"pinned":false}' 200 -H "Authorization: Bearer $T"
cv_http GET /notes "" 200 -H "Authorization: Bearer $T"
[ "$(jq -r '[.[].pinned] | any' <<<"$CV_HTTP_BODY")" = "false" ] || cv_fail "expected no pinned notes got $CV_HTTP_BODY" $LINENO
GOT=$(ids_in_list)
[ "$GOT" = "$A,$C,$B" ] || cv_fail "expected order by most recently changed $A,$C,$B got $GOT" $LINENO

# Cleanup
cv_step Cleanup "delete the notes" $LINENO
for n in $A $B $C; do cv_http DELETE "/notes/$n" "" -H "Authorization: Bearer $T" || true; done
echo "CODEVALID_TEST_ASSERTION_OK:api_25750298_8"
