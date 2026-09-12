#!/usr/bin/env bash
# shellcheck disable=SC2015  # `cond && pass || fail` is intentional; pass/fail always succeed
# Shared helpers for openarchiver-railway tests. Source this file; do not execute it.
# Secrets are never echoed. Only names, lengths, and pass/fail results are printed.

: "${BASE_URL:=http://127.0.0.1:8080}"
# The image installs dependencies and runs migrations on every start, so readiness is minutes, not
# seconds.
: "${TEST_TIMEOUT:=900}"

TEST_TMP="${TEST_TMP:-$(mktemp -d)}"
export TEST_TMP
_PASS=0; _FAIL=0

pass() { _PASS=$((_PASS+1)); printf '  PASS  %s\n' "$*"; }
fail() { _FAIL=$((_FAIL+1)); printf '  FAIL  %s\n' "$*" >&2; }
die()  { printf 'FATAL: %s\n' "$*" >&2; exit 1; }
section() { printf '\n== %s ==\n' "$*"; }
summary() { printf '\n%d passed, %d failed\n' "$_PASS" "$_FAIL"; [ "$_FAIL" -eq 0 ]; }

# here-strings, not pipes: `grep -q` exits on the first match and a pipe writer would get SIGPIPE,
# which `pipefail` reports as failure when the haystack is larger than the pipe buffer
assert_eq() { if [ "$2" = "$3" ]; then pass "$1 ($3)"; else fail "$1: expected [$2] got [$3]"; fi; }
assert_contains() { if grep -q -- "$2" <<<"$3"; then pass "$1"; else fail "$1: missing [$2]"; fi; }
assert_not_contains() { if grep -q -- "$2" <<<"$3"; then fail "$1: found forbidden [$2]"; else pass "$1"; fi; }

# curl still prints 000 through -w when it cannot connect, so `|| true`, never `|| echo 000`
http_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 30 "$@" || true; }
# TOKEN_FILE holds the bearer token and is never printed.
auth_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 60 -H "Authorization: Bearer $(cat "${TOKEN_FILE:?TOKEN_FILE not set}")" "$@" || true; }

wait_for_code() {
  local url=$1 want=$2 timeout=${3:-$TEST_TIMEOUT} start code
  start=$(date +%s)
  while :; do
    code=$(http_code "$url")
    [ "$code" = "$want" ] && return 0
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then printf 'timed out waiting for %s -> %s (last %s)\n' "$url" "$want" "$code" >&2; return 1; fi
    sleep 5
  done
}

# req_json TIMEOUT curl-args... -> body, retried while the response is not JSON
req_json() {
  local timeout=$1; shift
  local start body code
  start=$(date +%s)
  while :; do
    body=$(curl -s -w '\n%{http_code}' --max-time 60 "$@" || true)
    code=${body##*$'\n'}; body=${body%$'\n'*}
    if jq -e . >/dev/null 2>&1 <<<"$body"; then printf '%s' "$body"; return 0; fi
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then
      printf 'non-JSON response after %ss (HTTP %s) from: %s\n  body: %s\n' "$timeout" "$code" "$*" "$(head -c 200 <<<"$body")" >&2
      return 1
    fi
    sleep 5
  done
}
api_json() { req_json 120 -H "Authorization: Bearer $(cat "${TOKEN_FILE:?TOKEN_FILE not set}")" "$BASE_URL$1"; }

setup_status() { req_json 120 "$BASE_URL/api/v1/auth/status"; }
setup_code() {
  http_code -X POST "$BASE_URL/api/v1/auth/setup" -H 'Content-Type: application/json' \
    --data "$(jq -nc --arg e "$1" --arg p "$2" '{email:$e, password:$p, first_name:"In", last_name:"Truder"}')"
}
# login EMAIL PASSWORD_FILE TOKEN_OUT -> 0 on success
login() {
  local e=$1 pf=$2 out=$3 body code
  body=$(curl -s -w '\n%{http_code}' --max-time 60 -X POST "$BASE_URL/api/v1/auth/login" \
    -H 'Content-Type: application/json' \
    --data "$(jq -nc --arg e "$e" --rawfile p "$pf" '{email:$e, password:($p|rtrimstr("\n"))}')" || true)
  code=${body##*$'\n'}; body=${body%$'\n'*}
  [ "$code" = "200" ] || return 1
  jq -er '.accessToken' <<<"$body" > "$out" 2>/dev/null || return 1
  [ -s "$out" ]
}
login_code() {
  http_code -X POST "$BASE_URL/api/v1/auth/login" -H 'Content-Type: application/json' \
    --data "$(jq -nc --arg e "$1" --arg p "$2" '{email:$e, password:$p}')"
}
roles() { api_json /api/v1/iam/roles; }
users() { api_json /api/v1/users; }
system_settings() { api_json /api/v1/settings/system; }
# create_role NAME -> prints the role id
create_role() {
  req_json 120 -X POST "$BASE_URL/api/v1/iam/roles" \
    -H "Authorization: Bearer $(cat "${TOKEN_FILE:?TOKEN_FILE not set}")" \
    -H 'Content-Type: application/json' \
    --data "$(jq -nc --arg n "$1" '{name:$n, policies:[{action:"read", subject:"archive"}]}')" \
    | jq -r '.id // empty'
}
compose() { docker compose -f "$REPO_ROOT/compose.yaml" "$@"; }
