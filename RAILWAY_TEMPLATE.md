# Railway template configuration

The published template. Reproduce it from this file if it ever has to be rebuilt.

| | |
|---|---|
| Name | Open Archiver |
| Code | `open-archiver` |
| Category | Other |
| Image (public service) | `ghcr.io/youssefsiam38/openarchiver-railway:<version>` |
| Icon | `assets/icon.png` |
| Overview markdown | `marketplace/OVERVIEW.md` (Railway enforces its section headings) |

## Services

### `app` — public

| Field | Value |
|---|---|
| Source | `ghcr.io/youssefsiam38/openarchiver-railway:<version>` |
| Port | 8080 |
| Domain | generated, target port 8080 |
| Healthcheck | `/api/v1/auth/status`, timeout 900 |
| Volume | `/var/data/open-archiver` |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `APP_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` |
| `DATABASE_URL` | `${{Postgres.DATABASE_URL}}` |
| `REDIS_HOST` | `${{cache.RAILWAY_PRIVATE_DOMAIN}}` |
| `REDIS_PORT` | `6379` |
| `REDIS_PASSWORD` | `${{cache.REDIS_PASSWORD}}` |
| `REDIS_TLS_ENABLED` | `false` |
| `MEILI_HOST` | `http://${{search.RAILWAY_PRIVATE_DOMAIN}}:7700` |
| `MEILI_MASTER_KEY` | `${{search.MEILI_MASTER_KEY}}` |
| `JWT_SECRET` | `${{secret(64, "abcdef0123456789")}}` |
| `ENCRYPTION_KEY` | `${{secret(64, "abcdef0123456789")}}` |
| `OPENARCHIVER_ADMIN_EMAIL` | `admin@example.com` |
| `OPENARCHIVER_ADMIN_PASSWORD` | `${{secret(24)}}` |
| `PORT` | `8080` |
| `INDEXING_WORKER_MAX_OLD_SPACE_MB` | `1024` |
| `SYNC_FREQUENCY` | `*/15 * * * *` |
| `BODY_SIZE_LIMIT` | `100M` |

### `Postgres` — private

Railway's managed PostgreSQL. No extra configuration.

### `cache` — private

| Field | Value |
|---|---|
| Source | `valkey/valkey:8-alpine` |
| Start command | `valkey-server --requirepass ${REDIS_PASSWORD}` |
| Domain | none |
| Volume | `/data` |

| Variable | Value |
|---|---|
| `REDIS_PASSWORD` | `${{secret(32)}}` |

### `search` — private

| Field | Value |
|---|---|
| Source | `getmeili/meilisearch:v1.38` |
| Domain | none |
| Volume | `/meili_data` |

| Variable | Value |
|---|---|
| `MEILI_MASTER_KEY` | `${{secret(48)}}` |
| `MEILI_NO_ANALYTICS` | `true` |
| `MEILI_HTTP_ADDR` | `[::]:7700` |

## Notes

- Every variable has a value or a generator, so `railway deploy -t open-archiver` works without a
  TTY.
- **The healthcheck must be `/api/v1/auth/status` with a long timeout.** The image installs its
  dependencies and runs migrations on every start, so the service needs minutes, not seconds, and
  every other route answers 401 or redirects.
- **`PORT` and the domain's target port must match.** Railway runs its healthcheck against the value
  of `PORT`, defaulting to 8080.
- `MEILI_HTTP_ADDR=[::]:7700` makes Meilisearch bind dual-stack, which Railway's private network
  needs.
- Do not add `HOST`. The frontend reads it, and the image pins it to loopback so that every request
  passes the gate that holds the port shut until setup is claimed.
- `INDEXING_WORKER_MAX_OLD_SPACE_MB` is lowered from upstream's 2048. Raise it if you archive large
  attachments and have the memory to spare.
- `ENCRYPTION_KEY` must be exactly 64 hex characters; the `secret(64, "abcdef0123456789")` generator
  produces that.
