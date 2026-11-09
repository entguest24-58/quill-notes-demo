#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
# JWT_SECRET from .codevalid/docker-compose.yml (app service)
JWT_SECRET="${JWT_SECRET:-codevalid-test-secret}"
SUFFIX="$(date +%s%N)"
PASSWORD="Passw0rd-${SUFFIX}"

register_and_login() { # $1=email -> sets USER_ID, TOKEN
  cv_http POST /auth/register "{\"email\":\"$1\",\"password\":\"$PASSWORD\"}"
  [ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected 201 registering $1 got $CV_HTTP_STATUS" $LINENO
  USER_ID=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.id')
  cv_http POST /auth/login "{\"email\":\"$1\",\"password\":\"$PASSWORD\"}"
  [ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected 200 logging in $1 got $CV_HTTP_STATUS" $LINENO
  TOKEN=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.access_token // empty')
  [ -n "$TOKEN" ] || cv_fail "expected access_token from login got none" $LINENO
}

create_note() { # $1=token $2=title -> sets NOTE_ID
  cv_http POST /notes "{\"title\":\"$2\",\"body\":\"body-$SUFFIX\"}" -H "Authorization: Bearer $1"
  [ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected 201 creating note got $CV_HTTP_STATUS" $LINENO
  NOTE_ID=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.id')
}
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
b64url_decode() { local s; s=$(printf '%s' "$1" | tr '_-' '/+'); while [ $(( ${#s} % 4 )) -ne 0 ]; do s="$s="; done; printf '%s' "$s" | openssl base64 -d -A; }
make_jwt() { # $1=sub $2=iat $3=exp
  local h p sig
  h=$(printf '%s' '{"alg":"HS256","typ":"JWT"}' | b64url)
  p=$(printf '{"sub":"%s","iat":%s,"exp":%s}' "$1" "$2" "$3" | b64url)
  sig=$(printf '%s' "$h.$p" | openssl dgst -sha256 -hmac "$JWT_SECRET" -binary | b64url)
  printf '%s.%s.%s' "$h" "$p" "$sig"
}

# Given
cv_step Given "a registered person with one note" $LINENO
EMAIL="signin3_${SUFFIX}@example.com"
register_and_login "$EMAIL"
SETUP_TOKEN="$TOKEN"
create_note "$SETUP_TOKEN" "note-$SUFFIX"

# When
cv_step When "sign in and use a token that is 59 minutes old" $LINENO
cv_http POST /auth/login "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}"
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected 200 on sign-in got $CV_HTTP_STATUS" $LINENO
TOKEN=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.access_token // empty')
PAYLOAD=$(b64url_decode "$(printf '%s' "$TOKEN" | cut -d. -f2)")
IAT=$(printf '%s' "$PAYLOAD" | jq -r '.iat'); EXP=$(printf '%s' "$PAYLOAD" | jq -r '.exp')
# Waiting an hour is impractical: a token with the same claims, issued 59 minutes ago, stands in for "shortly before one hour".
NOW=$(date +%s)
OLD_TOKEN=$(make_jwt "$USER_ID" $((NOW - 3540)) $((NOW - 3540 + EXP - IAT)))
cv_http GET /notes "" -H "Authorization: Bearer $OLD_TOKEN"

# Then
cv_step Then "token lifetime is one hour and access is still granted near its end" $LINENO
[ $((EXP - IAT)) -eq 3600 ] || cv_fail "expected token lifetime 3600s got $((EXP - IAT))s" $LINENO
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected 200 with 59-minute-old token got $CV_HTTP_STATUS" $LINENO
printf '%s' "$CV_HTTP_BODY" | jq -e --argjson id "$NOTE_ID" 'any(.[]; .id == $id)' >/dev/null \
  || cv_fail "expected note $NOTE_ID in list got $CV_HTTP_BODY" $LINENO

# Cleanup
cv_step Cleanup "delete the created note" $LINENO
cv_http DELETE "/notes/$NOTE_ID" "" -H "Authorization: Bearer $SETUP_TOKEN"
echo "CODEVALID_TEST_ASSERTION_OK:api_98956333_3"
