#!/usr/bin/env bash
# shellcheck disable=SC2015
# Local smoke test. Run `docker compose build` first (CI does), or set OPENARCHIVER_RAILWAY_IMAGE.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
mkdir -p "$REPO_ROOT/test-output"; METRICS="$REPO_ROOT/test-output/metrics.txt"
LOCAL_PASSWORD='local-test-only-admin-password'
LOCAL_JWT='local-test-only-jwt-secret-not-for-production'
LOCAL_ENCRYPTION='00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff'
ADMIN_EMAIL='owner@example.invalid'
umask 077
printf '%s' "$LOCAL_PASSWORD" > "$TEST_TMP/pw"
TOKEN_FILE="$TEST_TMP/token"; export TOKEN_FILE

section "fresh stack (empty volumes)"
compose down -v --remove-orphans >/dev/null 2>&1 || true
t0=$(date +%s); compose up -d --no-build
wait_for_code "$BASE_URL/api/v1/auth/status" 200 900 && pass "frontend and API answer" || { compose logs --no-color app | tail -40; die "never became ready"; }
cold=$(( $(date +%s) - t0 )); echo "cold_start_seconds=$cold" | tee "$METRICS"

section "first-boot bootstrap"
logs=$(compose logs --no-color app)
assert_contains "app started on loopback" "starting Open Archiver on 127.0.0.1:3000" "$logs"
assert_contains "waited for the API before claiming setup" "the API is ready; ensuring the administrator account exists" "$logs"
assert_contains "administrator created" "administrator bootstrap complete" "$logs"
assert_contains "the door opened afterwards" "opening the public listener" "$logs"
for sec in "$LOCAL_PASSWORD" "$LOCAL_JWT" "$LOCAL_ENCRYPTION"; do
  assert_not_contains "secret not in logs (len ${#sec})" "$sec" "$logs"
done

section "the setup page is already claimed"
# Upstream refuses setup once a user exists. The wrapper's job is to be that user before anyone
# outside the container can reach the endpoint.
assert_eq "setup reports no setup needed" "false" "$(jq -r .needsSetup <<<"$(setup_status)")"
assert_eq "a stranger cannot run setup" "403" "$(setup_code 'intruder@example.invalid' 'intruder-password-long')"
code=$(login_code 'intruder@example.invalid' 'intruder-password-long')
[ "$code" != "200" ] && pass "the refused setup left no account behind (HTTP $code)" || fail "intruder account exists"

section "anonymous visitors are refused"
assert_eq "ingestion sources refused" "401" "$(http_code "$BASE_URL/api/v1/ingestion-sources")"
assert_eq "dashboard refused" "401" "$(http_code "$BASE_URL/api/v1/dashboard/stats")"
assert_eq "search refused" "401" "$(http_code "$BASE_URL/api/v1/search?query=test")"
assert_eq "user list refused" "401" "$(http_code "$BASE_URL/api/v1/users")"
code=$(login_code "$ADMIN_EMAIL" wrong-password-entirely)
[ "$code" != "200" ] && pass "wrong password rejected (HTTP $code)" || fail "wrong password accepted"

section "the app is not reachable except through the proxy"
assert_eq "frontend port is not published" "000" "$(http_code --max-time 5 "http://127.0.0.1:3000/")"
assert_eq "API port is not published" "000" "$(http_code --max-time 5 "http://127.0.0.1:4000/")"

section "signed in as the generated administrator"
login "$ADMIN_EMAIL" "$TEST_TMP/pw" "$TOKEN_FILE" && pass "administrator login" || die "login failed"
assert_eq "ingestion sources visible" "200" "$(auth_code "$BASE_URL/api/v1/ingestion-sources")"
assert_eq "dashboard visible" "200" "$(auth_code "$BASE_URL/api/v1/dashboard/stats")"
assert_eq "user list visible" "200" "$(auth_code "$BASE_URL/api/v1/users")"
u=$(api_json /api/v1/users)
assert_contains "the administrator is the only account" "$ADMIN_EMAIL" "$u"
assert_eq "exactly one account exists" "1" "$(jq -r 'length' <<<"$u")"
assert_eq "and it is a Super Admin" "Super Admin" "$(jq -r '.[0].userRoles[0].role.name' <<<"$u")"

section "search is wired to Meilisearch"
# `keywords`, not `query`: without it the API answers 400 "Keywords are required"
assert_eq "search answers when signed in" "200" "$(auth_code "$BASE_URL/api/v1/search?keywords=nothing")"
assert_eq "and reports an empty archive" "0" "$(jq -r .total <<<"$(api_json '/api/v1/search?keywords=nothing')")"

section "graceful shutdown (SIGTERM)"
t1=$(date +%s); compose stop -t 60 app; dur=$(( $(date +%s)-t1 ))
code=$(docker inspect --format '{{.State.ExitCode}}' "$(compose ps -a -q app)")
[ "$dur" -lt 60 ] && pass "stopped in ${dur}s without SIGKILL" || fail "stop took ${dur}s"
case "$code" in 0|143) pass "exit status after SIGTERM is $code" ;; *) fail "unexpected exit status $code" ;; esac
compose start app; wait_for_code "$BASE_URL/api/v1/auth/status" 200 900 && pass "restarted" || die "did not restart"
assert_contains "bootstrap is idempotent" "administrator bootstrap skipped" "$(compose logs --no-color app)"

section "fail-fast validation"
img=$(compose config --images | grep openarchiver | head -1)
base="-e APP_URL=http://example.invalid -e DATABASE_URL=postgresql://u:p@db:5432/x -e REDIS_HOST=cache -e MEILI_HOST=http://search:7700"
# shellcheck disable=SC2086  # deliberate word splitting of the shared flag list
run_img() { docker run --rm $base "$@" "$img" >"$TEST_TMP/ff.log" 2>&1; }
if run_img -e "MEILI_MASTER_KEY=k" -e "ENCRYPTION_KEY=$LOCAL_ENCRYPTION" -e "OPENARCHIVER_ADMIN_EMAIL=a@b.invalid" -e "OPENARCHIVER_ADMIN_PASSWORD=$LOCAL_PASSWORD"; then fail "should fail without JWT_SECRET"; else pass "exits without JWT_SECRET"; fi
assert_contains "names the missing variable" "JWT_SECRET" "$(cat "$TEST_TMP/ff.log")"
if run_img -e "MEILI_MASTER_KEY=k" -e "JWT_SECRET=a-very-secret-key-that-you-should-change" -e "ENCRYPTION_KEY=$LOCAL_ENCRYPTION" -e "OPENARCHIVER_ADMIN_EMAIL=a@b.invalid" -e "OPENARCHIVER_ADMIN_PASSWORD=$LOCAL_PASSWORD"; then fail "should refuse the example JWT secret"; else pass "refuses upstream's example JWT secret"; fi
assert_contains "explains the forged-session risk" "forge a session token" "$(cat "$TEST_TMP/ff.log")"
if run_img -e "MEILI_MASTER_KEY=aSampleMasterKey" -e "JWT_SECRET=$LOCAL_JWT" -e "ENCRYPTION_KEY=$LOCAL_ENCRYPTION" -e "OPENARCHIVER_ADMIN_EMAIL=a@b.invalid" -e "OPENARCHIVER_ADMIN_PASSWORD=$LOCAL_PASSWORD"; then fail "should refuse the example Meilisearch key"; else pass "refuses upstream's example Meilisearch key"; fi
if run_img -e "MEILI_MASTER_KEY=k" -e "JWT_SECRET=$LOCAL_JWT" -e "ENCRYPTION_KEY=tooshort" -e "OPENARCHIVER_ADMIN_EMAIL=a@b.invalid" -e "OPENARCHIVER_ADMIN_PASSWORD=$LOCAL_PASSWORD"; then fail "should reject a short encryption key"; else pass "rejects a malformed ENCRYPTION_KEY"; fi
assert_contains "explains the key format" "hex" "$(cat "$TEST_TMP/ff.log")"
if run_img -e "MEILI_MASTER_KEY=k" -e "JWT_SECRET=$LOCAL_JWT" -e "ENCRYPTION_KEY=$LOCAL_ENCRYPTION" -e "OPENARCHIVER_ADMIN_EMAIL=a@b.invalid" -e "OPENARCHIVER_ADMIN_PASSWORD=short"; then fail "should reject a short admin password"; else pass "rejects a short administrator password"; fi
if run_img -e "MEILI_MASTER_KEY=k" -e "JWT_SECRET=$LOCAL_JWT" -e "ENCRYPTION_KEY=$LOCAL_ENCRYPTION" -e "OPENARCHIVER_ADMIN_EMAIL=not-an-email" -e "OPENARCHIVER_ADMIN_PASSWORD=$LOCAL_PASSWORD"; then fail "should reject a malformed admin e-mail"; else pass "rejects a malformed administrator e-mail"; fi
if run_img -e "MEILI_MASTER_KEY=k" -e "JWT_SECRET=$LOCAL_JWT" -e "ENCRYPTION_KEY=$LOCAL_ENCRYPTION" -e "OPENARCHIVER_ADMIN_EMAIL=a@b.invalid" -e "OPENARCHIVER_ADMIN_PASSWORD=$LOCAL_PASSWORD" -e PORT=3000; then fail "should refuse a port collision"; else pass "refuses a port collision with the frontend"; fi
assert_contains "explains the collision" "cannot share a port" "$(cat "$TEST_TMP/ff.log")"
assert_not_contains "no secret echoed" "$LOCAL_PASSWORD" "$(cat "$TEST_TMP/ff.log")"

section "image metadata"
assert_eq "architecture" "amd64" "$(docker image inspect "$img" --format '{{.Architecture}}')"
labels=$(docker image inspect "$img" --format '{{json .Config.Labels}}')
for l in org.opencontainers.image.source org.opencontainers.image.revision org.opencontainers.image.version io.openarchiver-railway.upstream.version io.openarchiver-railway.caddy.version; do
  assert_contains "label $l" "\"$l\"" "$labels"
done
assert_contains "AGPL declared" "AGPL-3.0-only" "$labels"
assert_contains "upstream licence shipped" "GNU Affero General Public License" "$(compose exec -T app head -1 /usr/share/licenses/openarchiver-railway/OPENARCHIVER-LICENSE | tr -d '\r')"

section "metrics"
{ echo "image_bytes=$(docker image inspect "$img" --format '{{.Size}}')"
  docker stats --no-stream --format '{{.Name}} mem={{.MemUsage}}' | grep openarchiver-railway-test | sed 's/^/mem_/'; } | tee -a "$METRICS"
summary
