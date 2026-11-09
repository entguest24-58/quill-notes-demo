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

# create_note <token> <title> <body> -> sets NOTE_ID
create_note() {
  local tok="$1" title="$2" body="$3"
  cv_http POST /notes "$(jq -nc --arg t "$title" --arg b "$body" '{title:$t,body:$b}')" -H "Authorization: Bearer $tok"
  [ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected 201 creating note got $CV_HTTP_STATUS" $LINENO
  NOTE_ID="$(echo "$CV_HTTP_BODY" | jq -r '.id')"
}

# Given
cv_step Given "owner has a note already shared once with a recipient" $LINENO
OWNER_EMAIL="owner7_${SUFFIX}@example.com"
RECIP_EMAIL="recip7_${SUFFIX}@example.com"
register_and_login "$OWNER_EMAIL"; OWNER_TOKEN="$TOKEN"
register_and_login "$RECIP_EMAIL"; RECIP_TOKEN="$TOKEN"
create_note "$OWNER_TOKEN" "Dup ${SUFFIX}" "body7"
cv_prereq "first share" $LINENO
cv_http POST "/notes/${NOTE_ID}/shares" "{\"email\":\"$RECIP_EMAIL\"}" -H "Authorization: Bearer $OWNER_TOKEN"
case "$CV_HTTP_STATUS" in 200|201) ;; *) cv_fail "expected 2xx on first share got $CV_HTTP_STATUS" $LINENO ;; esac

# When
cv_step When "owner shares the same note with the same recipient again" $LINENO
cv_http POST "/notes/${NOTE_ID}/shares" "{\"email\":\"$RECIP_EMAIL\"}" -H "Authorization: Bearer $OWNER_TOKEN"
case "$CV_HTTP_STATUS" in 2??) ;; *) cv_fail "expected repeat share to be accepted (2xx) got $CV_HTTP_STATUS" $LINENO ;; esac

# Then
cv_step Then "the note appears exactly once in the recipient's shared-with-me list" $LINENO
cv_http GET /shared "" 200 -H "Authorization: Bearer $RECIP_TOKEN"
N="$(echo "$CV_HTTP_BODY" | jq --argjson id "$NOTE_ID" '[.[] | select(.id == $id)] | length')"
[ "$N" = "1" ] || cv_fail "expected note $NOTE_ID once in shared list got $N" $LINENO
TOTAL="$(echo "$CV_HTTP_BODY" | jq 'length')"
[ "$TOTAL" = "1" ] || cv_fail "expected exactly 1 shared entry got $TOTAL" $LINENO

# Cleanup
cv_step Cleanup "remove the share and the note" $LINENO
cv_http DELETE "/notes/${NOTE_ID}/shares" "{\"email\":\"$RECIP_EMAIL\"}" -H "Authorization: Bearer $OWNER_TOKEN" || true
cv_http DELETE "/notes/${NOTE_ID}" -H "Authorization: Bearer $OWNER_TOKEN" || true

echo "CODEVALID_TEST_ASSERTION_OK:api_79234096_7"
