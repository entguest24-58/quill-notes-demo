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
cv_step Given "an owner with a note, and an anonymous caller with no or a forged token" $LINENO
signup "anon_${SUFFIX}@example.com"; T=$TOKEN
TITLE="Secret $SUFFIX"; BODY="Private body $SUFFIX"
create_note "$T" "{\"title\":\"$TITLE\",\"body\":\"$BODY\",\"pinned\":false}"; NID=$NOTE_ID
cv_http GET "/notes/$NID" "" 200 -H "Authorization: Bearer $T"; BEFORE="$CV_HTTP_BODY"
BAD="eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.invalidsig"
RESULTS=""

# When
cv_step When "create, list, open, edit, pin and delete are attempted without a valid token" $LINENO
for auth in none bad; do
  if [ "$auth" = none ]; then H=(); else H=(-H "Authorization: Bearer $BAD"); fi
  cv_http POST /notes "{\"title\":\"anon $SUFFIX\"}" ${H[@]+"${H[@]}"}; RESULTS+="$auth:create:$CV_HTTP_STATUS "
  cv_http GET /notes "" ${H[@]+"${H[@]}"}; RESULTS+="$auth:list:$CV_HTTP_STATUS "
  grep -q "$SUFFIX" <<<"$CV_HTTP_BODY" && RESULTS+="$auth:list:LEAK "
  cv_http GET "/notes/$NID" "" ${H[@]+"${H[@]}"}; RESULTS+="$auth:open:$CV_HTTP_STATUS "
  grep -q "$SUFFIX" <<<"$CV_HTTP_BODY" && RESULTS+="$auth:open:LEAK "
  cv_http PATCH "/notes/$NID" '{"title":"hacked"}' ${H[@]+"${H[@]}"}; RESULTS+="$auth:edit:$CV_HTTP_STATUS "
  cv_http PATCH "/notes/$NID" '{"pinned":true}' ${H[@]+"${H[@]}"}; RESULTS+="$auth:pin:$CV_HTTP_STATUS "
  cv_http DELETE "/notes/$NID" "" ${H[@]+"${H[@]}"}; RESULTS+="$auth:delete:$CV_HTTP_STATUS "
done

# Then
cv_step Then "every action is 401, no note data returned, and the note is unchanged" $LINENO
for r in $RESULTS; do
  [ "${r##*:}" = "401" ] || cv_fail "expected 401 for every action got $r (all: $RESULTS)" $LINENO
done
cv_http GET "/notes/$NID" "" 200 -H "Authorization: Bearer $T"
jq -e --argjson b "$BEFORE" '. == $b' <<<"$CV_HTTP_BODY" >/dev/null || cv_fail "expected note unchanged $BEFORE got $CV_HTTP_BODY" $LINENO
cv_http GET /notes "" 200 -H "Authorization: Bearer $T"
[ "$(jq length <<<"$CV_HTTP_BODY")" = "1" ] || cv_fail "expected owner to have 1 note (no anon note created) got $CV_HTTP_BODY" $LINENO

# Cleanup
cv_step Cleanup "delete the owner's note" $LINENO
cv_http DELETE "/notes/$NID" "" -H "Authorization: Bearer $T" || true
echo "CODEVALID_TEST_ASSERTION_OK:api_25750298_15"
