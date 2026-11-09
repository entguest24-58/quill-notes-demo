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
cv_step Given "owner A shares a private note only with B; user C has no share" $LINENO
A_EMAIL="owner11_${SUFFIX}@example.com"
B_EMAIL="recip11_${SUFFIX}@example.com"
C_EMAIL="other11_${SUFFIX}@example.com"
register_and_login "$A_EMAIL"; A_TOKEN="$TOKEN"
register_and_login "$B_EMAIL"; B_TOKEN="$TOKEN"
register_and_login "$C_EMAIL"; C_TOKEN="$TOKEN"
SECRET_TITLE="Private title ${SUFFIX}"
SECRET_BODY="secret body ${SUFFIX}"
cv_http POST /notes "$(jq -nc --arg t "$SECRET_TITLE" --arg b "$SECRET_BODY" '{title:$t,body:$b}')" -H "Authorization: Bearer $A_TOKEN"
[ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected 201 creating note got $CV_HTTP_STATUS" $LINENO
NOTE_ID="$(echo "$CV_HTTP_BODY" | jq -r '.id')"
[ -n "$NOTE_ID" ] && [ "$NOTE_ID" != "null" ] || cv_fail "expected note id got none" $LINENO
cv_http POST "/notes/${NOTE_ID}/shares" "{\"email\":\"$B_EMAIL\"}" -H "Authorization: Bearer $A_TOKEN"
[ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected 201 sharing with B got $CV_HTTP_STATUS" $LINENO
cv_prereq "recipient B can read the shared note (control)" $LINENO
cv_http GET "/notes/${NOTE_ID}" "" -H "Authorization: Bearer $B_TOKEN"
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected 200 for recipient B reading shared note got $CV_HTTP_STATUS" $LINENO

# When
cv_step When "user C tries to open A's note and lists their shared-with-me notes" $LINENO
cv_http GET "/notes/${NOTE_ID}" "" -H "Authorization: Bearer $C_TOKEN"
S_READ="$CV_HTTP_STATUS"; B_READ="$CV_HTTP_BODY"
cv_http GET /shared "" -H "Authorization: Bearer $C_TOKEN"
S_LIST="$CV_HTTP_STATUS"; B_LIST="$CV_HTTP_BODY"

# Then
cv_step Then "C gets no note content and the note is not in C's list" $LINENO
if [ "$S_READ" = "200" ] || grep -qF "$SECRET_BODY" <<<"$B_READ" || grep -qF "$SECRET_TITLE" <<<"$B_READ"; then
  cv_fail "expected C to be refused reading A's unshared note got $S_READ with body $B_READ" $LINENO
fi
[ "$S_LIST" = "200" ] || cv_fail "expected 200 for C's shared list got $S_LIST" $LINENO
N="$(echo "$B_LIST" | jq --argjson id "$NOTE_ID" '[.[] | select(.id == $id)] | length')"
[ "$N" = "0" ] || cv_fail "expected A's note absent from C's shared list got $N occurrence(s)" $LINENO
grep -qF "$SECRET_BODY" <<<"$B_LIST" && cv_fail "expected no secret content in C's list got $B_LIST" $LINENO

# Cleanup
cv_step Cleanup "owner removes the share and deletes the note" $LINENO
cv_http DELETE "/notes/${NOTE_ID}/shares" "{\"email\":\"$B_EMAIL\"}" -H "Authorization: Bearer $A_TOKEN" || true
cv_http DELETE "/notes/${NOTE_ID}" -H "Authorization: Bearer $A_TOKEN" || true

echo "CODEVALID_TEST_ASSERTION_OK:api_79234096_11"
