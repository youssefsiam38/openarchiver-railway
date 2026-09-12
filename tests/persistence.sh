#!/usr/bin/env bash
# shellcheck disable=SC2015
# Persistence: the administrator, the completed setup and IAM state survive recreating every
# container on the same volumes.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
umask 077
printf '%s' 'local-test-only-admin-password' > "$TEST_TMP/pw"
TOKEN_FILE="$TEST_TMP/token"; export TOKEN_FILE
ADMIN_EMAIL='owner@example.invalid'

section "fresh stack"
compose down -v --remove-orphans >/dev/null 2>&1 || true
compose up -d --no-build; wait_for_code "$BASE_URL/api/v1/auth/status" 200 900 || die "not ready"

section "write state"
login "$ADMIN_EMAIL" "$TEST_TMP/pw" "$TOKEN_FILE" || die "login failed"
before_roles=$(jq -r 'length' <<<"$(roles)")
R=$(create_role "Persist Auditor"); [ -n "$R" ] && pass "role created ($R)" || die "role create failed"
assert_eq "role count grew" "$((before_roles+1))" "$(jq -r 'length' <<<"$(roles)")"
assert_eq "one administrator account" "1" "$(jq -r 'length' <<<"$(users)")"

section "recreate every container on the same volumes"
compose down >/dev/null; compose up -d --no-build
wait_for_code "$BASE_URL/api/v1/auth/status" 200 900 || die "not ready after recreate"
assert_contains "bootstrap left the account alone" "administrator bootstrap skipped" "$(compose logs --no-color app)"

section "verify"
assert_eq "setup is still complete" "false" "$(jq -r .needsSetup <<<"$(setup_status)")"
assert_eq "a stranger still cannot run setup" "403" "$(setup_code 'intruder@example.invalid' 'intruder-password-long')"
login "$ADMIN_EMAIL" "$TEST_TMP/pw" "$TOKEN_FILE" && pass "administrator password unchanged" || die "login failed after recreate"
r=$(roles)
assert_eq "role count retained" "$((before_roles+1))" "$(jq -r 'length' <<<"$r")"
assert_contains "the created role is still there" "Persist Auditor" "$r"
assert_eq "administrator account retained" "1" "$(jq -r 'length' <<<"$(users)")"
assert_eq "administrator is still Super Admin" "Super Admin" "$(jq -r '.[0].userRoles[0].role.name' <<<"$(users)")"
assert_eq "system settings readable" "en" "$(jq -r .language <<<"$(system_settings)")"
assert_eq "search still answers" "200" "$(auth_code "$BASE_URL/api/v1/search?keywords=nothing")"
R2=$(create_role "Persist Auditor Two"); [ -n "$R2" ] && pass "still writable after recreate" || fail "write failed after recreate"
summary
