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
cv_step Given "a registered, signed-in person with no notes" $LINENO
signup "bodylen_${SUFFIX}@example.com"; T=$TOKEN
B10000=$(head -c 10000 /dev/zero | tr '\0' 'a')
B10001=$(head -c 10001 /dev/zero | tr '\0' 'b')
[ ${#B10000} -eq 10000 ] && [ ${#B10001} -eq 10001 ] || cv_fail "expected 10000/10001-char bodies got ${#B10000}/${#B10001}" $LINENO

# When
cv_step When "they create notes with 10,000 and 10,001-character bodies" $LINENO
cv_http POST /notes "{\"title\":\"ok $SUFFIX\",\"body\":\"$B10000\"}" -H "Authorization: Bearer $T"; SOK=$CV_HTTP_STATUS; IDOK=$(jq -r '.id // empty' <<<"$CV_HTTP_BODY")
cv_http POST /notes "{\"title\":\"long $SUFFIX\",\"body\":\"$B10001\"}" -H "Authorization: Bearer $T"; SBAD=$CV_HTTP_STATUS

# Then
cv_step Then "10,000 accepted and stored intact; 10,001 refused and not stored" $LINENO
[ "$SOK" = "201" ] || cv_fail "expected 10000-char body 201 got $SOK" $LINENO
[ "${SBAD:0:1}" = "4" ] || cv_fail "expected 10001-char body refused (4xx) got $SBAD" $LINENO
cv_http GET "/notes/$IDOK" "" 200 -H "Authorization: Bearer $T"
[ "$(jq -r '.body|length' <<<"$CV_HTTP_BODY")" = "10000" ] || cv_fail "expected stored body length 10000" $LINENO
cv_http GET /notes "" 200 -H "Authorization: Bearer $T"
[ "$(jq length <<<"$CV_HTTP_BODY")" = "1" ] || cv_fail "expected 1 stored note got $(jq length <<<"$CV_HTTP_BODY")" $LINENO
jq -e --arg t "long $SUFFIX" 'any(.[]; .title==$t)|not' <<<"$CV_HTTP_BODY" >/dev/null || cv_fail "expected 10001-body note not stored" $LINENO

# Cleanup
cv_step Cleanup "delete created notes" $LINENO
for id in $(jq -r '.[].id' <<<"$CV_HTTP_BODY"); do cv_http DELETE "/notes/$id" "" -H "Authorization: Bearer $T" || true; done
echo "CODEVALID_TEST_ASSERTION_OK:api_25750298_4"
