# Open Archiver on Railway

Keep every message, permanently and searchably. **Open Archiver** connects to Google Workspace,
Microsoft 365, a generic IMAP mailbox or a PST/EML/mbox export, copies the mail into storage you
control, and gives you full-text search across all of it with attachments indexed. This repository
is a **community-maintained Railway template** for
[Open Archiver](https://github.com/LogicLabs-OU/OpenArchiver). It is **not affiliated with the Open
Archiver project**.

<!-- DEPLOY_BUTTON_START -->
Deploy button is added once the template is published.
<!-- DEPLOY_BUTTON_END -->

> **Read this before deploying.** A fresh Open Archiver shows a setup page that creates the first
> Super Admin. Upstream correctly refuses that page once any account exists, but on a public URL the
> race is real: whoever loads it first owns an archive of an entire organisation's mail. This
> template completes the setup inside the container before the service is reachable. See
> [SECURITY.md](SECURITY.md).

> **Licence.** Open Archiver is **AGPL-3.0**. This template deploys the upstream release unmodified.
> If you let other people use your deployment over a network you are a distributor under AGPL §13
> and must be able to offer them the corresponding source; see
> [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The wrapper code here is MIT.

## What you get

| Service | Source | Public | Volume |
|---|---|---|---|
| `app` | `ghcr.io/youssefsiam38/openarchiver-railway:<version>` wrapping `logiclabshq/open-archiver:v0.6.0` | yes | `/var/data/open-archiver` — archived mail and attachments |
| `db` | Railway PostgreSQL | no | managed |
| `cache` | `valkey/valkey:8-alpine` | no | `/data` — job queues |
| `search` | `getmeili/meilisearch:v1.38` | no | `/meili_data` — search index |

| Component | Version |
|---|---|
| Open Archiver | 0.6.0 |
| Caddy (the gate that holds the port shut until setup is done) | 2.10.2 |
| Wrapper | see [releases](https://github.com/youssefsiam38/openarchiver-railway/releases) |

**This is the heaviest template in this family.** The application container alone sits at roughly
650 MB of memory idle, before any mailbox is ingested, and there are four services. Budget
accordingly.

## First run

1. Click **Deploy on Railway**. Nothing has to be filled in: the administrator password, the JWT
   secret, the mailbox-credential encryption key and the Meilisearch key are all generated.
2. **The first deploy is slow.** The upstream image installs its dependencies and runs database
   migrations on every start, which takes several minutes before the service answers.
3. Read `OPENARCHIVER_ADMIN_PASSWORD` in the Railway dashboard under the `app` service's Variables
   tab, clicking it to reveal.
4. Open the service's public URL and sign in as `admin@example.com` (or whatever you set
   `OPENARCHIVER_ADMIN_EMAIL` to) with that password. Change the password in the app afterwards.
5. Add an ingestion source: Google Workspace, Microsoft 365, IMAP, or upload a PST/EML/mbox file.
   For the OAuth providers, register `https://<your-domain>/api/v1/oauth/callback` as the redirect
   URI.
6. Watch the dashboard as mail is archived and indexed.

## Environment variables

| Variable | Required | Set by template | Description |
|---|---|---|---|
| `OPENARCHIVER_ADMIN_EMAIL` | yes | `admin@example.com` | Wrapper: e-mail of the Super Admin created on first start. Change it to your own. |
| `OPENARCHIVER_ADMIN_PASSWORD` | yes | generated `${{secret(24)}}` | Wrapper: that account's password. At least 12 characters. Ignored once setup is complete. |
| `OPENARCHIVER_ADMIN_FIRST_NAME`, `OPENARCHIVER_ADMIN_LAST_NAME` | no | `Archive`, `Administrator` | Wrapper: the name on that account. |
| `APP_URL` | yes | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | Public URL. Sets the CORS origin and forms the OAuth redirect URI, so a wrong value breaks sign-in and mailbox connection. |
| `JWT_SECRET` | yes | generated `${{secret(64, "abcdef0123456789")}}` | Signs session tokens. The wrapper refuses upstream's example value. |
| `ENCRYPTION_KEY` | yes | generated 64 hex characters | Encrypts the stored credentials of every mailbox you connect. Changing it makes existing ones unreadable. |
| `STORAGE_ENCRYPTION_KEY` | no | unset | Encrypts archived files at rest. 64 hex characters when set. |
| `DATABASE_URL` | yes | reference to the `db` service | PostgreSQL connection string. |
| `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD` | yes | references to `cache` | Job queues. `REDIS_TLS_ENABLED` stays `false` on the private network. |
| `MEILI_HOST`, `MEILI_MASTER_KEY` | yes | references to `search` | Search index. The wrapper refuses upstream's example key. |
| `PORT` | no | `8080` | Port the gate listens on. Railway probes its healthcheck here, so keep it equal to the domain's target port. |
| `OPENARCHIVER_INTERNAL_PORT`, `PORT_BACKEND` | no | `3000`, `4000` | Loopback ports for the frontend and the API. Never exposed. |
| `INDEXING_WORKER_MAX_OLD_SPACE_MB` | no | `1024` | Heap ceiling for the indexing worker. Upstream's default is 2048; lower it further on a small plan. |
| `BODY_SIZE_LIMIT` | no | `100M` | Upload limit for PST/mbox imports. Use the local-path import for multi-gigabyte files. |
| `SYNC_FREQUENCY` | no | `*/15 * * * *` | How often live mailboxes are re-synced. Upstream's default is every minute. |
| `TIKA_URL` | no | unset | Point at an Apache Tika service for richer attachment extraction. Without it the built-in PDF parser is used. |

Everything in Open Archiver's
[`.env.example`](https://github.com/LogicLabs-OU/OpenArchiver/blob/main/.env.example) works as usual.

## Persistent paths

| Path | Service | Contents | Backup |
|---|---|---|---|
| `/var/data/open-archiver` | `app` | archived messages and attachments | `railway volume files download` |
| PostgreSQL | `db` | metadata, users, roles, jobs | `pg_dump` |
| `/meili_data` | `search` | search index (rebuildable) | not required |
| `/data` | `cache` | job queues | not required |

## Local development

```bash
docker compose build
docker compose up -d
```

Then open http://127.0.0.1:8080 and sign in as `owner@example.invalid`. The compose file uses obvious
local-test-only secrets; do not reuse them.

Tests:

```bash
tests/static.sh       # syntax, shellcheck, pinning, the setup race cannot be reopened
tests/smoke.sh        # cold start, setup already claimed, anonymous refusal, fail-fast checks
tests/persistence.sh  # administrator and IAM state survive recreating every container
tests/railway-smoke.sh https://your-app.up.railway.app   # against a deployment
```

## Known upstream behaviour

- The image runs `pnpm install` and database migrations **on every container start**, so each deploy
  and restart costs several minutes and needs registry access.
- The indexing worker defaults to a 2 GB heap. The template lowers it; raise it again if you archive
  large attachments and have the memory.

## Documentation

| File | Contents |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | service graph, what the wrapper does, boot sequence |
| [RAILWAY_TEMPLATE.md](RAILWAY_TEMPLATE.md) | exact template configuration |
| [SECURITY.md](SECURITY.md) | threat model, what is exposed, reporting |
| [UPSTREAM.md](UPSTREAM.md) | upstream provenance and how to bump it |
| [MAINTENANCE.md](MAINTENANCE.md) | release process and update checklist |
| [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) | licences of everything shipped |
| [MARKETPLACE_AUDIT.md](MARKETPLACE_AUDIT.md) | why this template was built |

## Licence

Wrapper code in this repository: MIT ([LICENSE](LICENSE)). The application it deploys is AGPL-3.0
and stays under its own licence; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
