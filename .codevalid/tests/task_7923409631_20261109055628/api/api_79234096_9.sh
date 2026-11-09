#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
PASSWORD="Passw0rd!${SUFFIX: -6}"

# register_and_login <email> -> sets TOKEN
register_and_login() {
  local email="$1"
  cv_http POST /auth/register "{\"email\":\"$email\",\"password\":\"$PASSWORD\"}"
  [ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected 201 registering $email got $CV_HTTP_STATUS" $LINENO
  cv_http POST /auth/login "{\"email\":\"$email\",\"password\":\"$PASSWORD\"}"
  [ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected 200 logging in $email got $CV_HTTP_STATUS" $LINENO
  TOKEN="$(echo "$CV_HTTP_BODY" | jq -r '.access_token')"
  [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ] || cv_fail "expected access_token for $email got none" $LINENO
}

# Given
cv_step Given "owner A with a note, attacker B and third account C exist" $LINENO
A_EMAIL="owner9_${SUFFIX}@example.com"
B_EMAIL="attacker9_${SUFFIX}@example.com"
C_EMAIL="third9_${SUFFIX}@example.com"
register_and_login "$A_EMAIL"; A_TOKEN="$TOKEN"
register_and_login "$B_EMAIL"; B_TOKEN="$TOKEN"
register_and_login "$C_EMAIL"; C_TOKEN="$TOKEN"
cv_http POST /notes "$(jq -nc --arg t "Private ${SUFFIX}" '{title:$t,body:"secret body 9"}')" -H "Authorization: Bearer $A_TOKEN"
[ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected 201 creating note got $CV_HTTP_STATUS" $LINENO
NOTE_ID="$(echo "$CV_HTTP_BODY" | jq -r '.id')"
[ -n "$NOTE_ID" ] && [ "$NOTE_ID" != "null" ] || cv_fail "expected note id got none" $LINENO
MISSING_ID=$((NOTE_ID + 100000000))

# When
cv_step When "B tries to share A's note with C, and (for comparison) a note that does not exist" $LINENO
cv_http POST "/notes/${NOTE_ID}/shares" "{\"email\":\"$C_EMAIL\"}" -H "Authorization: Bearer $B_TOKEN"
S_ATTACK="$CV_HTTP_STATUS"; B_ATTACK="$CV_HTTP_BODY"
cv_http POST "/notes/${MISSING_ID}/shares" "{\"email\":\"$C_EMAIL\"}" -H "Authorization: Bearer $B_TOKEN"
S_MISSING="$CV_HTTP_STATUS"; B_MISSING="$CV_HTTP_BODY"

# Then
cv_step Then "response matches a missing note (not found) and C has no share of A's note" $LINENO
[ "$S_ATTACK" = "404" ] || cv_fail "expected 404 (not found) when B shares A's note got $S_ATTACK body $B_ATTACK" $LINENO
[ "$S_ATTACK" = "$S_MISSING" ] || cv_fail "expected same status as missing note ($S_MISSING) got $S_ATTACK" $LINENO
[ "$B_ATTACK" = "$B_MISSING" ] || cv_fail "expected same body as missing note ($B_MISSING) got $B_ATTACK" $LINENO
if echo "$B_ATTACK" | grep -q "secret body 9\|Private ${SUFFIX}"; then
  cv_fail "expected no note content in response got $B_ATTACK" $LINENO
fi
cv_http GET /shared "" 200 -H "Authorization: Bearer $C_TOKEN"
N="$(echo "$CV_HTTP_BODY" | jq --argjson id "$NOTE_ID" '[.[] | select(.id == $id)] | length')"
[ "$N" = "0" ] || cv_fail "expected no share of A's note for C got $N" $LINENO
cv_http GET /shared "" 200 -H "Authorization: Bearer $B_TOKEN"
N="$(echo "$CV_HTTP_BODY" | jq --argjson id "$NOTE_ID" '[.[] | select(.id == $id)] | length')"
[ "$N" = "0" ] || cv_fail "expected no share of A's note for B got $N" $LINENO

# Cleanup
cv_step Cleanup "owner deletes the note" $LINENO
cv_http DELETE "/notes/${NOTE_ID}" -H "Authorization: Bearer $A_TOKEN" || true

echo "CODEVALID_TEST_ASSERTION_OK:api_79234096_9"
