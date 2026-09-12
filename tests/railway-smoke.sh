#!/usr/bin/env bash
# shellcheck disable=SC2015
# Public smoke test against a deployed instance.
#   tests/railway-smoke.sh https://your-app.up.railway.app
# Optional: ADMIN_EMAIL=you@example.com ADMIN_PASSWORD_FILE=/path/to/file
#   STATE_OUT=/path/state.json (create a role) / STATE_IN=/path/state.json (verify after redeploy)
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
BASE_URL=${1:?usage: railway-smoke.sh https://domain}; BASE_URL=${BASE_URL%/}; export BASE_URL
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
host=${BASE_URL#https://}

section "TLS and routing"
# Railway's edge serves 404 for a few seconds while a deployment takes over, so wait rather than
# racing the cutover when this runs straight after a deploy.
wait_for_code "$BASE_URL/api/v1/auth/status" 200 900 || true
assert_eq "API answers over https" "200" "$(http_code "$BASE_URL/api/v1/auth/status")"
assert_contains "valid certificate" "SSL certificate verify ok" "$(curl -sv -o /dev/null "$BASE_URL/api/v1/auth/status" 2>&1 || true)"
assert_contains "http -> https" "https://$host" "$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 20 "http://$host/api/v1/auth/status")"

section "the setup page is already claimed"
assert_eq "setup reports no setup needed" "false" "$(jq -r .needsSetup <<<"$(setup_status)")"
assert_eq "a stranger cannot run setup" "403" "$(setup_code 'intruder@example.invalid' 'intruder-password-long')"
code=$(login_code 'intruder@example.invalid' 'intruder-password-long')
[ "$code" != "200" ] && pass "the refused setup left no account behind (HTTP $code)" || fail "intruder account exists"

section "anonymous visitors are refused"
assert_eq "ingestion sources refused" "401" "$(http_code "$BASE_URL/api/v1/ingestion-sources")"
assert_eq "dashboard refused" "401" "$(http_code "$BASE_URL/api/v1/dashboard/stats")"
assert_eq "search refused" "401" "$(http_code "$BASE_URL/api/v1/search?keywords=test")"
assert_eq "user list refused" "401" "$(http_code "$BASE_URL/api/v1/users")"

if [ -n "${ADMIN_PASSWORD_FILE:-}" ]; then
  section "signed in through the public domain"
  TOKEN_FILE="$TEST_TMP/token"; export TOKEN_FILE
  email=${ADMIN_EMAIL:?ADMIN_EMAIL must be set alongside ADMIN_PASSWORD_FILE}
  code=$(login_code "$email" wrong-password-entirely)
  [ "$code" != "200" ] && pass "wrong password rejected (HTTP $code)" || fail "wrong password accepted"
  login "$email" "$ADMIN_PASSWORD_FILE" "$TOKEN_FILE" && pass "sign in with the generated password" || die "login failed"
  assert_eq "ingestion sources visible" "200" "$(auth_code "$BASE_URL/api/v1/ingestion-sources")"
  assert_eq "search answers" "200" "$(auth_code "$BASE_URL/api/v1/search?keywords=nothing")"
  u=$(users)
  assert_eq "exactly one account exists" "1" "$(jq -r 'length' <<<"$u")"
  assert_eq "and it is a Super Admin" "Super Admin" "$(jq -r '.[0].userRoles[0].role.name' <<<"$u")"

  if [ -n "${STATE_OUT:-}" ]; then
    section "write state"
    before=$(jq -r 'length' <<<"$(roles)")
    R=$(create_role "Railway Auditor"); [ -n "$R" ] && pass "role created ($R)" || die "role create failed"
    jq -n --arg r "$R" --argjson n "$((before+1))" '{role:$r, name:"Railway Auditor", count:$n}' > "$STATE_OUT"
    pass "state written"
  fi

  if [ -n "${STATE_IN:-}" ]; then
    section "verify state after redeploy"
    r=$(roles)
    assert_eq "role count retained" "$(jq -r .count "$STATE_IN")" "$(jq -r 'length' <<<"$r")"
    assert_contains "the created role is still there" "$(jq -r .name "$STATE_IN")" "$r"
    assert_eq "administrator account retained" "1" "$(jq -r 'length' <<<"$(users)")"
    R2=$(create_role "Railway Auditor Two"); [ -n "$R2" ] && pass "still writable" || fail "write failed"
  fi
fi
summary
