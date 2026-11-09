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
cv_step Given "two owners share three notes changed at different times with one recipient" $LINENO
OWNER_A="ownerA2_${SUFFIX}@example.com"
OWNER_C="ownerC2_${SUFFIX}@example.com"
RECIP_EMAIL="recip2_${SUFFIX}@example.com"
register_and_login "$OWNER_A"; TOKEN_A="$TOKEN"
register_and_login "$OWNER_C"; TOKEN_C="$TOKEN"
register_and_login "$RECIP_EMAIL"; RECIP_TOKEN="$TOKEN"
create_note "$TOKEN_A" "A first ${SUFFIX}" "a1"; N1="$NOTE_ID"
sleep 1.2
create_note "$TOKEN_C" "C second ${SUFFIX}" "c2"; N2="$NOTE_ID"
sleep 1.2
create_note "$TOKEN_A" "A third ${SUFFIX}" "a3"; N3="$NOTE_ID"
for pair in "$N1:$TOKEN_A" "$N2:$TOKEN_C" "$N3:$TOKEN_A"; do
  nid="${pair%%:*}"; tok="${pair#*:}"
  cv_prereq "share note $nid with recipient" $LINENO
  cv_http POST "/notes/${nid}/shares" "{\"email\":\"$RECIP_EMAIL\"}" -H "Authorization: Bearer $tok"
  case "$CV_HTTP_STATUS" in 200|201) ;; *) cv_fail "expected 2xx sharing note $nid got $CV_HTTP_STATUS" $LINENO ;; esac
done

# When
cv_step When "recipient retrieves the shared-with-me list" $LINENO
cv_http GET /shared "" 200 -H "Authorization: Bearer $RECIP_TOKEN"

# Then
cv_step Then "the list holds exactly the shared notes, most recently changed first" $LINENO
IDS="$(echo "$CV_HTTP_BODY" | jq -c '[.[].id]')"
EXPECTED="[$N3,$N2,$N1]"
[ "$IDS" = "$EXPECTED" ] || cv_fail "expected shared list ids $EXPECTED got $IDS" $LINENO
B3="$(echo "$CV_HTTP_BODY" | jq -r '.[0].body')"
[ "$B3" = "a3" ] || cv_fail "expected first note body 'a3' got '$B3'" $LINENO

# Cleanup
cv_step Cleanup "remove the shares and notes" $LINENO
for pair in "$N1:$TOKEN_A" "$N2:$TOKEN_C" "$N3:$TOKEN_A"; do
  nid="${pair%%:*}"; tok="${pair#*:}"
  cv_http DELETE "/notes/${nid}/shares" "{\"email\":\"$RECIP_EMAIL\"}" -H "Authorization: Bearer $tok" || true
  cv_http DELETE "/notes/${nid}" -H "Authorization: Bearer $tok" || true
done

echo "CODEVALID_TEST_ASSERTION_OK:api_79234096_2"
