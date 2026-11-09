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
count_notes() {
  cv_http GET /notes "" 200 -H "Authorization: Bearer $1"
  COUNT=$(jq 'length' <<<"$CV_HTTP_BODY")
}

# Given
cv_step Given "a registered, signed-in person with no notes" $LINENO
signup "titlelen_${SUFFIX}@example.com"; T=$TOKEN
T200=$(printf 'a%.0s' $(seq 1 200))
T201=$(printf 'b%.0s' $(seq 1 201))
[ ${#T200} -eq 200 ] && [ ${#T201} -eq 201 ] || cv_fail "expected 200/201-char titles got ${#T200}/${#T201}" $LINENO

# When
cv_step When "they create notes with 1, 200, empty, missing and 201-character titles" $LINENO
cv_http POST /notes '{"title":"x","body":"one"}' -H "Authorization: Bearer $T"; S1=$CV_HTTP_STATUS; ID1=$(jq -r '.id // empty' <<<"$CV_HTTP_BODY")
cv_http POST /notes "{\"title\":\"$T200\",\"body\":\"two hundred\"}" -H "Authorization: Bearer $T"; S200=$CV_HTTP_STATUS; ID200=$(jq -r '.id // empty' <<<"$CV_HTTP_BODY")
cv_http POST /notes '{"title":"","body":"empty"}' -H "Authorization: Bearer $T"; SE=$CV_HTTP_STATUS
cv_http POST /notes '{"body":"missing"}' -H "Authorization: Bearer $T"; SM=$CV_HTTP_STATUS
cv_http POST /notes "{\"title\":\"$T201\",\"body\":\"too long\"}" -H "Authorization: Bearer $T"; S201=$CV_HTTP_STATUS

# Then
cv_step Then "1 and 200 chars accepted; others refused and not stored" $LINENO
[ "$S1" = "201" ] || cv_fail "expected 1-char title 201 got $S1" $LINENO
[ "$S200" = "201" ] || cv_fail "expected 200-char title 201 got $S200" $LINENO
for s in "empty:$SE" "missing:$SM" "201chars:$S201"; do
  st=${s#*:}
  [ "${st:0:1}" = "4" ] || cv_fail "expected ${s%%:*} title refused (4xx) got $st" $LINENO
done
count_notes "$T"
[ "$COUNT" = "2" ] || cv_fail "expected exactly 2 stored notes got $COUNT: $CV_HTTP_BODY" $LINENO
jq -e 'all(.[]; .title=="x" or (.title|length)==200)' <<<"$CV_HTTP_BODY" >/dev/null || cv_fail "expected only valid notes stored got $CV_HTTP_BODY" $LINENO

# Cleanup
cv_step Cleanup "delete created notes" $LINENO
for id in $(jq -r '.[].id' <<<"$CV_HTTP_BODY"); do cv_http DELETE "/notes/$id" "" -H "Authorization: Bearer $T" || true; done
echo "CODEVALID_TEST_ASSERTION_OK:api_25750298_3"
