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
cv_step Given "owner account exists with a note" $LINENO
OWNER_EMAIL="owner6_${SUFFIX}@example.com"
OWNER_UPPER="OWNER6_${SUFFIX}@EXAMPLE.COM"
register_and_login "$OWNER_EMAIL"; OWNER_TOKEN="$TOKEN"
create_note "$OWNER_TOKEN" "Self ${SUFFIX}" "body6"

# When
cv_step When "owner shares the note with their own email, as written and in different case" $LINENO
cv_http POST "/notes/${NOTE_ID}/shares" "{\"email\":\"$OWNER_EMAIL\"}" -H "Authorization: Bearer $OWNER_TOKEN"
S1="$CV_HTTP_STATUS"
cv_http POST "/notes/${NOTE_ID}/shares" "{\"email\":\"$OWNER_UPPER\"}" -H "Authorization: Bearer $OWNER_TOKEN"
S2="$CV_HTTP_STATUS"

# Then
cv_step Then "both requests are refused and no share appears in the owner's shared list" $LINENO
case "$S1" in 4??) ;; *) cv_fail "expected 4xx refusal sharing with own email got $S1" $LINENO ;; esac
case "$S2" in 4??) ;; *) cv_fail "expected 4xx refusal sharing with own email in other case got $S2" $LINENO ;; esac
cv_http GET /shared "" 200 -H "Authorization: Bearer $OWNER_TOKEN"
N="$(echo "$CV_HTTP_BODY" | jq --argjson id "$NOTE_ID" '[.[] | select(.id == $id)] | length')"
[ "$N" = "0" ] || cv_fail "expected note not shared with its owner got $N entries" $LINENO

# Cleanup
cv_step Cleanup "remove the note" $LINENO
cv_http DELETE "/notes/${NOTE_ID}" -H "Authorization: Bearer $OWNER_TOKEN" || true

echo "CODEVALID_TEST_ASSERTION_OK:api_79234096_6"
