# Upstream provenance

## Open Archiver

| | |
|---|---|
| Project | [Open Archiver](https://github.com/LogicLabs-OU/OpenArchiver) |
| Version deployed | 0.6.0 |
| Licence | AGPL-3.0-only |
| Image | `docker.io/logiclabshq/open-archiver:v0.6.0` |
| Digest | `sha256:3c240bf852d604b73a5229c0a22e2e69987e8e9cfe7241710598ca6187c08b83` |
| Source for the tag | https://github.com/LogicLabs-OU/OpenArchiver/tree/v0.6.0 |
| Platforms | linux/amd64, linux/arm64 |

## Caddy

| | |
|---|---|
| Project | [Caddy](https://github.com/caddyserver/caddy) |
| Version | 2.10.2 |
| Licence | Apache-2.0 |
| Image | `docker.io/library/caddy:2.10-alpine` |
| Digest | `sha256:4c6e91c6ed0e2fa03efd5b44747b625fec79bc9cd06ac5235a779726618e530d` |

Only the `caddy` binary is copied out of that image, in a build stage. It is a static Go binary, so
it runs unchanged on the Alpine base.

## Companion services

| Component | Version | Licence | Notes |
|---|---|---|---|
| PostgreSQL | Railway managed | PostgreSQL Licence | metadata, users, roles, jobs |
| Valkey | `valkey/valkey:8-alpine` | BSD-3-Clause | job queues; Redis-compatible |
| Meilisearch | `getmeili/meilisearch:v1.38` | MIT | full-text index |

These are pulled from their publishers at deploy time and are not redistributed by this repository.

## What this repository changes

Nothing in the application. The wrapper image is `FROM logiclabshq/open-archiver` plus:

| Added | Path | Why |
|---|---|---|
| Caddy binary | `/usr/local/bin/caddy` | holds the public port shut until setup is claimed |
| entrypoint | `/usr/local/bin/openarchiver-railway-entrypoint` | validation, readiness waits, supervision |
| bootstrap | `/usr/local/lib/openarchiver-railway/bootstrap-admin.mjs` | completes setup before the service is reachable |
| licences | `/usr/share/licenses/openarchiver-railway/` | AGPL and Apache-2.0 texts shipped with the binary |
| `HOST=127.0.0.1`, `PORT=8080`, `OPENARCHIVER_INTERNAL_PORT=3000`, `JWT_EXPIRES_IN=7d`, `STORAGE_TYPE=local` | env | keeps the app off the public interface and supplies defaults upstream requires but does not default |
| OCI labels | image metadata | source, revision, version, upstream version, Caddy version |

No patches, no forks, no rebuilt assets.

## AGPL obligations

Open Archiver is AGPL-3.0-only. Running it as a network service makes you a distributor under §13:
anyone who uses your instance is entitled to the corresponding source of the version you run. The
version is recorded in the image label `io.openarchiver-railway.upstream.version` and in the tag
above, so pointing users at the matching upstream tag satisfies it. The wrapper's own code is MIT
and is published in this repository.

## Bumping the upstream version

1. Find the new release at https://github.com/LogicLabs-OU/OpenArchiver/releases and read it for
   schema or variable changes.
2. Resolve the new digest:
   ```bash
   docker buildx imagetools inspect logiclabshq/open-archiver:vX.Y.Z --format '{{.Manifest.Digest}}'
   ```
3. Update `OPENARCHIVER_IMAGE` and `OPENARCHIVER_VERSION` in `Dockerfile`, plus the version tables in
   `README.md` and this file.
4. `tests/static.sh && docker compose build && tests/smoke.sh && tests/persistence.sh`.
5. Follow [MAINTENANCE.md](MAINTENANCE.md) to release and to update the template image.

**Check the setup endpoint every time.** The wrapper depends on `GET /v1/auth/status` returning
`{"needsSetup":boolean}` and on `POST /v1/auth/setup` returning 201 once and 403 thereafter. It also
depends on the frontend proxying `/api/v1/*` to the API. Re-read `.env.example` too: new required
variables appear there before they appear in the documentation.
