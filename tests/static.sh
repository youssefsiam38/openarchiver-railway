#!/usr/bin/env bash
# shellcheck disable=SC2015
# Static validation: shell and JavaScript syntax, shellcheck, compose config, image pins.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
cd "$REPO_ROOT"
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"

section "syntax"
for f in scripts/*.sh; do
  if sh -n "$f" 2>/dev/null; then pass "parses: $f"; else fail "syntax error: $f"; fi
done
for f in tests/*.sh; do
  if bash -n "$f" 2>/dev/null; then pass "parses: $f"; else fail "syntax error: $f"; fi
done
if node --check scripts/bootstrap-admin.mjs 2>/dev/null; then pass "bootstrap-admin.mjs parses"; else fail "bootstrap-admin.mjs syntax"; fi

section "shellcheck"
if command -v shellcheck >/dev/null; then
  if shellcheck -s sh scripts/*.sh; then pass "shellcheck scripts"; else fail "shellcheck scripts"; fi
  if shellcheck -x -s bash tests/*.sh; then pass "shellcheck tests"; else fail "shellcheck tests"; fi
else
  echo "  SKIP  shellcheck not installed"
fi

section "compose"
if docker compose -f compose.yaml config >/dev/null; then pass "compose config"; else fail "compose config"; fi

section "image pins"
df=$(cat Dockerfile)
assert_contains "Open Archiver pinned by tag and digest" 'logiclabshq/open-archiver:v0.6.0@sha256:' "$df"
assert_contains "Caddy pinned by tag and digest" 'caddy:2.10-alpine@sha256:' "$df"
assert_contains "entrypoint is the wrapper" 'ENTRYPOINT \["/usr/local/bin/openarchiver-railway-entrypoint"\]' "$df"
assert_contains "frontend bound to loopback in the image" 'HOST=127.0.0.1' "$df"
assert_contains "JWT_EXPIRES_IN defaulted" 'JWT_EXPIRES_IN=7d' "$df"
cy=$(grep -oE 'getmeili/meilisearch:v[0-9.]+' compose.yaml | head -1)
[ -n "$cy" ] && pass "Meilisearch version-pinned in compose ($cy)" || fail "Meilisearch not version-pinned"
pg=$(grep -oE 'postgres:[0-9]+-alpine' compose.yaml | head -1)
[ -n "$pg" ] && pass "PostgreSQL version-pinned in compose ($pg)" || fail "PostgreSQL not version-pinned"
vk=$(grep -oE 'valkey/valkey:[0-9]+-alpine' compose.yaml | head -1)
[ -n "$vk" ] && pass "Valkey version-pinned in compose ($vk)" || fail "Valkey not version-pinned"

section "the setup race cannot be reopened"
ep=$(cat scripts/entrypoint.sh)
assert_contains "the admin exists before the door opens" 'opening the public listener' "$ep"
assert_contains "requires an administrator password" 'OPENARCHIVER_ADMIN_PASSWORD' "$ep"
assert_contains "refuses upstream's example JWT secret" 'a-very-secret-key-that-you-should-change' "$ep"
assert_contains "refuses upstream's example Meilisearch key" 'aSampleMasterKey' "$ep"
assert_contains "refuses upstream's example Redis password" 'defaultredispassword' "$ep"
assert_contains "validates the mailbox-credential key length" 'exactly 64 hex characters' "$ep"
assert_contains "the generated config is validated before use" 'caddy validate' "$ep"
bs=$(cat scripts/bootstrap-admin.mjs)
assert_contains "bootstrap checks the setup state first" 'needsSetup' "$bs"
assert_contains "bootstrap is idempotent" 'already complete' "$bs"

section "workflows"
override=$(grep -oE '[A-Z_]*_RAILWAY_IMAGE' compose.yaml | head -1)
for wf in .github/workflows/*.yml; do
  if grep -q 'candidate' "$wf" && ! grep -q "$override" "$wf"; then
    fail "$wf tests a candidate image but never sets $override"
  else
    pass "image override name matches compose in $wf"
  fi
  if grep -qE 'uses: .*@[0-9a-f]{40}' "$wf" && ! grep -qE 'uses: .*@v[0-9]+\s*$' "$wf"; then
    pass "actions pinned by SHA in $wf"
  else
    fail "unpinned action in $wf"
  fi
done

section "log streams"
# Railway colours a log line by the stream it arrived on: routine lines on stderr show as errors.
if grep -q '^log()' scripts/entrypoint.sh && ! grep '^log()' scripts/entrypoint.sh | grep -q '>&2'; then
  pass "routine logs go to stdout"
else
  fail "log() writes to stderr; Railway would show every start-up line as an error"
fi
if grep '^fail()' scripts/entrypoint.sh | grep -q '>&2'; then pass "failures go to stderr"; else fail "fail() does not write to stderr"; fi
assert_not_contains "the admin bootstrap logs to stdout too" "console.error(\`[openarchiver-railway]" "$(cat scripts/bootstrap-admin.mjs)"

section "the cache password is expanded by a shell"
# Railway does not expand variables in a start command: `--requirepass ${REDIS_PASSWORD}` sets the
# password to that literal string and every worker fails with WRONGPASS. The compose file runs the
# same shape as the template so the local stack would catch it.
cache_cmd=$(docker compose -f compose.yaml config --format json | jq -r '.services.cache.command | join(" ")')
assert_contains "the local cache command goes through a shell" 'exec valkey-server --requirepass' "$cache_cmd"
assert_contains "and the template records the same" 'sh -c .exec valkey-server --requirepass' "$(cat RAILWAY_TEMPLATE.md)"

section "no tracked secrets"
if git rev-parse --git-dir >/dev/null 2>&1; then
  if git grep -nIE '(BEGIN [A-Z ]*PRIVATE KEY|ghp_[A-Za-z0-9]{20,}|xox[baprs]-)' -- . >/dev/null 2>&1; then
    fail "credential pattern in tracked files"
  else
    pass "no credential patterns in tracked files"
  fi
  if git ls-files --error-unmatch .env >/dev/null 2>&1; then fail ".env is tracked"; else pass ".env not tracked"; fi
else
  echo "  SKIP  not a git checkout"
fi
summary
