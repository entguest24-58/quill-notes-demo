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
cv_step Given "owner A shares a note with recipient B; account C exists" $LINENO
A_EMAIL="owner10_${SUFFIX}@example.com"
B_EMAIL="recip10_${SUFFIX}@example.com"
C_EMAIL="third10_${SUFFIX}@example.com"
register_and_login "$A_EMAIL"; A_TOKEN="$TOKEN"
register_and_login "$B_EMAIL"; B_TOKEN="$TOKEN"
register_and_login "$C_EMAIL"; C_TOKEN="$TOKEN"
cv_http POST /notes "$(jq -nc --arg t "Shared ${SUFFIX}" '{title:$t,body:"body 10"}')" -H "Authorization: Bearer $A_TOKEN"
[ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected 201 creating note got $CV_HTTP_STATUS" $LINENO
NOTE_ID="$(echo "$CV_HTTP_BODY" | jq -r '.id')"
[ -n "$NOTE_ID" ] && [ "$NOTE_ID" != "null" ] || cv_fail "expected note id got none" $LINENO
cv_http POST "/notes/${NOTE_ID}/shares" "{\"email\":\"$B_EMAIL\"}" -H "Authorization: Bearer $A_TOKEN"
[ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected 201 owner sharing with B got $CV_HTTP_STATUS" $LINENO
cv_http GET /shared "" -H "Authorization: Bearer $B_TOKEN"
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected 200 listing B's shared notes got $CV_HTTP_STATUS" $LINENO
N="$(echo "$CV_HTTP_BODY" | jq --argjson id "$NOTE_ID" '[.[] | select(.id == $id)] | length')"
[ "$N" = "1" ] || cv_fail "expected B to see the shared note got $N" $LINENO
MISSING_ID=$((NOTE_ID + 100000000))

# When
cv_step When "recipient B tries to re-share A's note with C, and (for comparison) a missing note" $LINENO
cv_http POST "/notes/${NOTE_ID}/shares" "{\"email\":\"$C_EMAIL\"}" -H "Authorization: Bearer $B_TOKEN"
S_ATTACK="$CV_HTTP_STATUS"; B_ATTACK="$CV_HTTP_BODY"
cv_http POST "/notes/${MISSING_ID}/shares" "{\"email\":\"$C_EMAIL\"}" -H "Authorization: Bearer $B_TOKEN"
S_MISSING="$CV_HTTP_STATUS"; B_MISSING="$CV_HTTP_BODY"

# Then
cv_step Then "re-share behaves like a missing note and C has no share" $LINENO
[ "$S_ATTACK" = "404" ] || cv_fail "expected 404 (not found) when recipient re-shares got $S_ATTACK body $B_ATTACK" $LINENO
[ "$S_ATTACK" = "$S_MISSING" ] || cv_fail "expected same status as missing note ($S_MISSING) got $S_ATTACK" $LINENO
[ "$B_ATTACK" = "$B_MISSING" ] || cv_fail "expected same body as missing note ($B_MISSING) got $B_ATTACK" $LINENO
cv_http GET /shared "" 200 -H "Authorization: Bearer $C_TOKEN"
N="$(echo "$CV_HTTP_BODY" | jq --argjson id "$NOTE_ID" '[.[] | select(.id == $id)] | length')"
[ "$N" = "0" ] || cv_fail "expected no share of A's note for C got $N" $LINENO

# Cleanup
cv_step Cleanup "owner deletes the note" $LINENO
cv_http DELETE "/notes/${NOTE_ID}" -H "Authorization: Bearer $A_TOKEN" || true

echo "CODEVALID_TEST_ASSERTION_OK:api_79234096_10"
