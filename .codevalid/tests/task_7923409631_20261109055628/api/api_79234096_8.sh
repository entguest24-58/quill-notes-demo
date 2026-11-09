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
cv_step Given "owner with a note and a recipient account exist" $LINENO
OWNER_EMAIL="owner8_${SUFFIX}@example.com"
RECIP_EMAIL="recip8_${SUFFIX}@example.com"
register_and_login "$OWNER_EMAIL"; OWNER_TOKEN="$TOKEN"
register_and_login "$RECIP_EMAIL"; RECIP_TOKEN="$TOKEN"
create_note "$OWNER_TOKEN" "Guarded ${SUFFIX}" "body8"
BAD_TOKEN="not.a.valid.token${SUFFIX}"

# When
cv_step When "share and shared-list calls are made with no token and with an invalid token" $LINENO
cv_http POST "/notes/${NOTE_ID}/shares" "{\"email\":\"$RECIP_EMAIL\"}"
S_SHARE_NONE="$CV_HTTP_STATUS"
cv_http POST "/notes/${NOTE_ID}/shares" "{\"email\":\"$RECIP_EMAIL\"}" -H "Authorization: Bearer $BAD_TOKEN"
S_SHARE_BAD="$CV_HTTP_STATUS"
cv_http GET /shared
S_LIST_NONE="$CV_HTTP_STATUS"; B_LIST_NONE="$CV_HTTP_BODY"
cv_http GET /shared "" -H "Authorization: Bearer $BAD_TOKEN"
S_LIST_BAD="$CV_HTTP_STATUS"; B_LIST_BAD="$CV_HTTP_BODY"

# Then
cv_step Then "all calls are refused as unauthorized, nothing is returned and no share exists" $LINENO
[ "$S_SHARE_NONE" = "401" ] || cv_fail "expected 401 sharing without token got $S_SHARE_NONE" $LINENO
[ "$S_SHARE_BAD" = "401" ] || cv_fail "expected 401 sharing with invalid token got $S_SHARE_BAD" $LINENO
[ "$S_LIST_NONE" = "401" ] || cv_fail "expected 401 listing shared without token got $S_LIST_NONE" $LINENO
[ "$S_LIST_BAD" = "401" ] || cv_fail "expected 401 listing shared with invalid token got $S_LIST_BAD" $LINENO
for b in "$B_LIST_NONE" "$B_LIST_BAD"; do
  if echo "$b" | jq -e 'type == "array"' >/dev/null 2>&1; then
    cv_fail "expected no notes returned to unauthenticated caller got array $b" $LINENO
  fi
done
cv_http GET /shared "" 200 -H "Authorization: Bearer $RECIP_TOKEN"
N="$(echo "$CV_HTTP_BODY" | jq --argjson id "$NOTE_ID" '[.[] | select(.id == $id)] | length')"
[ "$N" = "0" ] || cv_fail "expected no share created by unauthenticated calls got $N" $LINENO

# Cleanup
cv_step Cleanup "remove the note" $LINENO
cv_http DELETE "/notes/${NOTE_ID}" -H "Authorization: Bearer $OWNER_TOKEN" || true

echo "CODEVALID_TEST_ASSERTION_OK:api_79234096_8"
