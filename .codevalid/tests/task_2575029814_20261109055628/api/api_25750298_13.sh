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
cv_step Given "pinned and unpinned notes, where the older ones are changed most recently" $LINENO
signup "order_${SUFFIX}@example.com"; T=$TOKEN
create_note "$T" '{"title":"P-old","pinned":true}'; P1=$NOTE_ID
create_note "$T" '{"title":"U-old","pinned":false}'; U1=$NOTE_ID
sleep 1.2
create_note "$T" '{"title":"P-new","pinned":true}'; P2=$NOTE_ID
create_note "$T" '{"title":"U-new","pinned":false}'; U2=$NOTE_ID
sleep 1.2
cv_prereq "change the older notes so they become most recently changed" $LINENO
cv_http PATCH "/notes/$P1" '{"body":"changed later"}' 200 -H "Authorization: Bearer $T"
cv_http PATCH "/notes/$U1" '{"body":"changed later"}' 200 -H "Authorization: Bearer $T"

# When
cv_step When "they list their notes" $LINENO
cv_http GET /notes "" 200 -H "Authorization: Bearer $T"

# Then
cv_step Then "pinned first, and within each group most recently changed first" $LINENO
GOT=$(jq -r '[.[].id]|join(",")' <<<"$CV_HTTP_BODY")
EXP="$P1,$P2,$U1,$U2"
[ "$GOT" = "$EXP" ] || cv_fail "expected order $EXP (P-old,P-new,U-old,U-new) got $GOT: $(jq -c '[.[]|{id,title,pinned,updated_at}]' <<<"$CV_HTTP_BODY")" $LINENO

# Cleanup
cv_step Cleanup "delete the notes" $LINENO
for id in $P1 $P2 $U1 $U2; do cv_http DELETE "/notes/$id" "" -H "Authorization: Bearer $T" || true; done
echo "CODEVALID_TEST_ASSERTION_OK:api_25750298_13"
