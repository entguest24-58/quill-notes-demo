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
cv_step Given "recipient has two shared notes, the newer one listed first" $LINENO
OWNER_EMAIL="owner3_${SUFFIX}@example.com"
RECIP_EMAIL="recip3_${SUFFIX}@example.com"
register_and_login "$OWNER_EMAIL"; OWNER_TOKEN="$TOKEN"
register_and_login "$RECIP_EMAIL"; RECIP_TOKEN="$TOKEN"
create_note "$OWNER_TOKEN" "Older ${SUFFIX}" "old"; N_OLD="$NOTE_ID"
sleep 1.2
create_note "$OWNER_TOKEN" "Newer ${SUFFIX}" "new"; N_NEW="$NOTE_ID"
for nid in "$N_OLD" "$N_NEW"; do
  cv_prereq "share note $nid with recipient" $LINENO
  cv_http POST "/notes/${nid}/shares" "{\"email\":\"$RECIP_EMAIL\"}" -H "Authorization: Bearer $OWNER_TOKEN"
  case "$CV_HTTP_STATUS" in 200|201) ;; *) cv_fail "expected 2xx sharing note $nid got $CV_HTTP_STATUS" $LINENO ;; esac
done
cv_prereq "confirm initial order newer-first" $LINENO
cv_http GET /shared "" 200 -H "Authorization: Bearer $RECIP_TOKEN"
INIT="$(echo "$CV_HTTP_BODY" | jq -c '[.[].id]')"
[ "$INIT" = "[$N_NEW,$N_OLD]" ] || cv_fail "expected initial shared order [$N_NEW,$N_OLD] got $INIT" $LINENO
sleep 1.2

# When
cv_step When "owner edits the older-changed note" $LINENO
cv_http PATCH "/notes/${N_OLD}" '{"body":"edited later"}' 200 -H "Authorization: Bearer $OWNER_TOKEN"

# Then
cv_step Then "recipient's shared-with-me list shows the edited note first" $LINENO
cv_http GET /shared "" 200 -H "Authorization: Bearer $RECIP_TOKEN"
IDS="$(echo "$CV_HTTP_BODY" | jq -c '[.[].id]')"
[ "$IDS" = "[$N_OLD,$N_NEW]" ] || cv_fail "expected shared order [$N_OLD,$N_NEW] after edit got $IDS" $LINENO
B="$(echo "$CV_HTTP_BODY" | jq -r '.[0].body')"
[ "$B" = "edited later" ] || cv_fail "expected first note body 'edited later' got '$B'" $LINENO

# Cleanup
cv_step Cleanup "remove the shares and notes" $LINENO
for nid in "$N_OLD" "$N_NEW"; do
  cv_http DELETE "/notes/${nid}/shares" "{\"email\":\"$RECIP_EMAIL\"}" -H "Authorization: Bearer $OWNER_TOKEN" || true
  cv_http DELETE "/notes/${nid}" -H "Authorization: Bearer $OWNER_TOKEN" || true
done

echo "CODEVALID_TEST_ASSERTION_OK:api_79234096_3"
