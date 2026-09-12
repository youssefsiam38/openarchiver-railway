#!/bin/sh
# openarchiver-railway entrypoint.
#
#   1. validate variables (names only; values are never printed)
#   2. run the app on loopback, complete the one-shot setup, and only then open the public port
#   3. supervise the app and the public listener; if either exits, the container exits
set -u

log()  { printf '[openarchiver-railway] %s\n' "$*" >&2; }
fail() { log "FATAL: $*"; exit 1; }

: "${OPENARCHIVER_INTERNAL_PORT:=3000}"
: "${PORT_BACKEND:=4000}"
: "${JWT_EXPIRES_IN:=7d}"
: "${STORAGE_TYPE:=local}"
: "${STORAGE_LOCAL_ROOT_PATH:=/var/data/open-archiver}"
: "${BODY_SIZE_LIMIT:=100M}"
: "${APP_READY_TIMEOUT:=900}"
BOOTSTRAP=/usr/local/lib/openarchiver-railway/bootstrap-admin.mjs
CADDYFILE=/etc/openarchiver-railway/Caddyfile

PUBLIC_PORT="${PORT:-8080}"
for p in "$PUBLIC_PORT" "$OPENARCHIVER_INTERNAL_PORT" "$PORT_BACKEND"; do
  case "$p" in ''|*[!0-9]*) fail "ports must be numbers, got \"$p\"" ;; esac
done
[ "$PUBLIC_PORT" != "$OPENARCHIVER_INTERNAL_PORT" ] || fail "PORT and OPENARCHIVER_INTERNAL_PORT are both $PUBLIC_PORT. The public listener and the frontend cannot share a port."
[ "$PUBLIC_PORT" != "$PORT_BACKEND" ] || fail "PORT and PORT_BACKEND are both $PUBLIC_PORT. The public listener and the API cannot share a port."
[ "$OPENARCHIVER_INTERNAL_PORT" != "$PORT_BACKEND" ] || fail "OPENARCHIVER_INTERNAL_PORT and PORT_BACKEND are both $PORT_BACKEND. The frontend and the API cannot share a port."

missing=""
for v in APP_URL DATABASE_URL REDIS_HOST MEILI_HOST MEILI_MASTER_KEY JWT_SECRET ENCRYPTION_KEY \
         OPENARCHIVER_ADMIN_EMAIL OPENARCHIVER_ADMIN_PASSWORD; do
  eval "val=\${$v:-}"
  [ -n "$val" ] || missing="$missing $v"
done
[ -z "$missing" ] || fail "missing required variable(s):$missing"

case "$APP_URL" in
  http://?*|https://?*) ;;
  *) fail "APP_URL must be the full public URL of this instance, starting with http:// or https://. It sets the CORS origin and the OAuth redirect URI, so a wrong value breaks sign-in and mailbox connection." ;;
esac
: "${ORIGIN:=$APP_URL}"

# Upstream's .env.example ships these placeholders. Deploying with them is the difference between
# an archive only you can read and one anybody can mint a session for.
[ "$JWT_SECRET" != "a-very-secret-key-that-you-should-change" ] || fail "JWT_SECRET is still the placeholder from upstream's .env.example. Anyone could forge a session token. Generate one with: openssl rand -hex 32"
[ "${#JWT_SECRET}" -ge 32 ] || fail "JWT_SECRET must be at least 32 characters"
[ "$MEILI_MASTER_KEY" != "aSampleMasterKey" ] || fail "MEILI_MASTER_KEY is still the placeholder from upstream's .env.example. Generate a new one."
[ "${REDIS_PASSWORD:-}" != "defaultredispassword" ] || fail "REDIS_PASSWORD is still the placeholder from upstream's .env.example. Generate a new one."

# ENCRYPTION_KEY protects the stored credentials of every mailbox this archive connects to.
case "$ENCRYPTION_KEY" in
  *[!0-9a-fA-F]*) fail "ENCRYPTION_KEY must be a 64-character hex string. Generate one with: openssl rand -hex 32" ;;
esac
[ "${#ENCRYPTION_KEY}" -eq 64 ] || fail "ENCRYPTION_KEY must be exactly 64 hex characters (32 bytes). Generate one with: openssl rand -hex 32"

if [ -n "${STORAGE_ENCRYPTION_KEY:-}" ] && [ "${#STORAGE_ENCRYPTION_KEY}" -ne 64 ]; then
  fail "STORAGE_ENCRYPTION_KEY must be exactly 64 hex characters (32 bytes) when set"
fi

[ "${#OPENARCHIVER_ADMIN_PASSWORD}" -ge 12 ] || fail "OPENARCHIVER_ADMIN_PASSWORD must be at least 12 characters"

if [ "$STORAGE_TYPE" = "local" ]; then
  mkdir -p "$STORAGE_LOCAL_ROOT_PATH" || fail "cannot create $STORAGE_LOCAL_ROOT_PATH"
  [ -w "$STORAGE_LOCAL_ROOT_PATH" ] || fail "$STORAGE_LOCAL_ROOT_PATH is not writable"
fi

mkdir -p /etc/openarchiver-railway || fail "cannot create /etc/openarchiver-railway"
cat > "$CADDYFILE" <<EOF
{
	admin off
	auto_https off
	persist_config off
}
:${PUBLIC_PORT} {
	request_body {
		max_size 0
	}
	reverse_proxy 127.0.0.1:${OPENARCHIVER_INTERNAL_PORT}
}
EOF
caddy validate --config "$CADDYFILE" --adapter caddyfile >/dev/null 2>&1 \
  || fail "generated Caddy configuration is invalid"

# The frontend is a SvelteKit node adapter: it reads HOST and PORT. Keep it on loopback and give the
# public port to Caddy instead.
HOST=127.0.0.1
PORT="$OPENARCHIVER_INTERNAL_PORT"
PORT_FRONTEND="$OPENARCHIVER_INTERNAL_PORT"
OPENARCHIVER_BACKEND_URL="http://127.0.0.1:${PORT_BACKEND}"
export HOST PORT PORT_FRONTEND PORT_BACKEND ORIGIN JWT_EXPIRES_IN STORAGE_TYPE \
       STORAGE_LOCAL_ROOT_PATH BODY_SIZE_LIMIT OPENARCHIVER_BACKEND_URL

log "starting Open Archiver on ${HOST}:${OPENARCHIVER_INTERNAL_PORT} (API on ${PORT_BACKEND}) behind the public listener on :${PUBLIC_PORT}"
log "the first start installs dependencies and runs database migrations, which takes several minutes"
docker-entrypoint.sh pnpm docker-start:oss &
app_pid=$!

ready() {
  node -e "
fetch('$1').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1));
" 2>/dev/null
}
deadline=$(( $(date +%s) + APP_READY_TIMEOUT ))
until ready "${OPENARCHIVER_BACKEND_URL}/v1/auth/status"; do
  kill -0 "$app_pid" 2>/dev/null || fail "Open Archiver exited during start-up"
  [ "$(date +%s)" -lt "$deadline" ] || fail "the API did not become ready within ${APP_READY_TIMEOUT}s"
  sleep 5
done
log "the API is ready; ensuring the administrator account exists"
node "$BOOTSTRAP" || fail "administrator bootstrap failed"

until ready "http://127.0.0.1:${OPENARCHIVER_INTERNAL_PORT}/api/v1/auth/status"; do
  kill -0 "$app_pid" 2>/dev/null || fail "Open Archiver exited during start-up"
  [ "$(date +%s)" -lt "$deadline" ] || fail "the frontend did not become ready within ${APP_READY_TIMEOUT}s"
  sleep 5
done

log "opening the public listener"
caddy run --config "$CADDYFILE" --adapter caddyfile &
caddy_pid=$!

# A signalled shutdown is not a failure. Without this the supervised children exit non-zero on
# SIGTERM and the container would report a crash every time the platform stops it.
shutting_down=0
# shellcheck disable=SC2317  # invoked by the trap below
on_signal() {
  shutting_down=1
  log "received a stop signal; shutting down"
  kill -TERM "$app_pid" "$caddy_pid" 2>/dev/null
}
trap on_signal TERM INT

# BusyBox ash has no reliable `wait -n`, so poll both children and exit as soon as either does.
while :; do
  if ! kill -0 "$app_pid" 2>/dev/null; then
    wait "$app_pid"; status=$?
    log "Open Archiver exited with status ${status}; shutting down"
    break
  fi
  if ! kill -0 "$caddy_pid" 2>/dev/null; then
    wait "$caddy_pid"; status=$?
    log "the public listener exited with status ${status}; shutting down"
    break
  fi
  sleep 1
done
kill -TERM "$app_pid" "$caddy_pid" 2>/dev/null
[ "$shutting_down" = "1" ] && exit 0
exit "$status"
