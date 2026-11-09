#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"

# Logs in and leaves status/body in CV_HTTP_*.
login() { cv_http POST /auth/login "$(jq -nc --arg e "$1" --arg p "$2" '{email:$e,password:$p}')"; }
register() { cv_http POST /auth/register "$(jq -nc --arg e "$1" --arg p "$2" '{email:$e,password:$p}')"; }

# Given
cv_step Given "a unique email, valid password and privileged extra fields" $LINENO
EMAIL="reg7_${SUFFIX}@example.com"
PASS="ValidPass123"
PAYLOAD=$(jq -nc --arg e "$EMAIL" --arg p "$PASS" '{email:$e,password:$p,role:"admin",is_admin:true,admin:true,id:1}')

# When
cv_step When "register with role/admin fields included" $LINENO
cv_http POST /auth/register "$PAYLOAD"
S="$CV_HTTP_STATUS"; B="$CV_HTTP_BODY"

# Then
cv_step Then "either refused, or created without privileged attributes" $LINENO
case "$S" in
  201|200)
    for f in role is_admin admin; do
      v=$(echo "$B" | jq -c --arg f "$f" '.[$f] // null')
      case "$v" in null|false|'"user"') ;; *) cv_fail "expected $f not applied got $f=$v in $B" $LINENO ;; esac
    done
    [ "$(echo "$B" | jq -r '.id')" != "1" ] || cv_fail "client-supplied id=1 was applied: $B" $LINENO
    login "$EMAIL" "$PASS"
    [ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected login 200 got $CV_HTTP_STATUS" $LINENO
    TOKEN=$(echo "$CV_HTTP_BODY" | jq -r '.access_token')
    PAYLOAD_JSON=$(echo "$TOKEN" | cut -d. -f2 | tr '_-' '/+')
    while [ $(( ${#PAYLOAD_JSON} % 4 )) -ne 0 ]; do PAYLOAD_JSON="${PAYLOAD_JSON}="; done
    CLAIMS=$(echo "$PAYLOAD_JSON" | base64 -d 2>/dev/null || true)
    echo "token claims: $CLAIMS"
    echo "$CLAIMS" | jq -e '(.role // null) != "admin" and (.is_admin // false) != true and (.admin // false) != true' >/dev/null       || cv_fail "token carries privileged claims: $CLAIMS" $LINENO
    ;;
  4??) login "$EMAIL" "$PASS"
       [ "$CV_HTTP_STATUS" = "401" ] || cv_fail "registration refused but account exists (login $CV_HTTP_STATUS)" $LINENO ;;
  *) cv_fail "expected 201 (defaults) or 4xx refusal got $S: $B" $LINENO ;;
esac

# Cleanup
cv_step Cleanup "no user-delete endpoint exists; unique email leaves no conflict" $LINENO
echo "user $EMAIL left in place if created (no delete route)"

echo "CODEVALID_TEST_ASSERTION_OK:api_13648970_7"
