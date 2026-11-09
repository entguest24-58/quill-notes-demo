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
cv_step Given "owner has a note and an email with no account is chosen" $LINENO
OWNER_EMAIL="owner4_${SUFFIX}@example.com"
GHOST_EMAIL="ghost4_${SUFFIX}@example.com"
register_and_login "$OWNER_EMAIL"; OWNER_TOKEN="$TOKEN"
create_note "$OWNER_TOKEN" "Private ${SUFFIX}" "body4"

# When
cv_step When "owner shares the note with the email that has no account" $LINENO
cv_http POST "/notes/${NOTE_ID}/shares" "{\"email\":\"$GHOST_EMAIL\"}" -H "Authorization: Bearer $OWNER_TOKEN"
SHARE_STATUS="$CV_HTTP_STATUS"

# Then
cv_step Then "request is refused as not found and no share exists for a later account with that email" $LINENO
[ "$SHARE_STATUS" = "404" ] || cv_fail "expected 404 sharing with unknown email got $SHARE_STATUS" $LINENO
cv_http POST /auth/register "{\"email\":\"$GHOST_EMAIL\",\"password\":\"$PASSWORD\"}" 201
cv_http POST /auth/login "{\"email\":\"$GHOST_EMAIL\",\"password\":\"$PASSWORD\"}" 200
GHOST_TOKEN="$(echo "$CV_HTTP_BODY" | jq -r '.access_token')"
cv_http GET /shared "" 200 -H "Authorization: Bearer $GHOST_TOKEN"
N="$(echo "$CV_HTTP_BODY" | jq 'length')"
[ "$N" = "0" ] || cv_fail "expected no shared notes for that email got $N" $LINENO

# Cleanup
cv_step Cleanup "remove the note" $LINENO
cv_http DELETE "/notes/${NOTE_ID}" -H "Authorization: Bearer $OWNER_TOKEN" || true

echo "CODEVALID_TEST_ASSERTION_OK:api_79234096_4"
