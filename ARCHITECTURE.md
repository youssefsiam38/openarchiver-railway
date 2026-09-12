# Architecture

## Service graph

```
                       internet
                          │  https
                          ▼
        ┌─────────────────────────────────────┐
        │  app  (public)                      │
        │                                     │
        │   Caddy  :$PORT                     │  opened only after setup is claimed
        │     │                               │
        │     ▼                               │
        │   frontend 127.0.0.1:3000  ──┐      │  SvelteKit, proxies /api
        │   API      127.0.0.1:4000  ◄─┘      │  Express
        │   workers: ingestion, indexing,     │
        │            sync scheduler           │
        │   volume /var/data/open-archiver    │  archived mail
        └───────┬──────────┬─────────┬────────┘
       private  │          │         │  private
                ▼          ▼         ▼
        ┌────────────┐ ┌────────┐ ┌──────────────┐
        │ db         │ │ cache  │ │ search       │
        │ PostgreSQL │ │ Valkey │ │ Meilisearch  │
        │ managed    │ │ /data  │ │ /meili_data  │
        └────────────┘ └────────┘ └──────────────┘
```

Only `app` has a public domain. It runs five processes: the SvelteKit frontend, the Express API, and
the ingestion, indexing and scheduler workers. That is upstream's own topology; the wrapper does not
split it.

## Why a wrapper image

Open Archiver's first run is a one-shot setup page that creates the first Super Admin.
`UserService` refuses it once any user exists:

```ts
const isFirstUser = Number(userCountResult[0].count) === 0;
if (!isFirstUser) {
    throw Error('This operation is only allowed upon initial setup.');
}
```

That is the right design, and verified against the stock image: the second call answers 403 with
"Setup has already been completed." The gap is timing, not logic. Railway publishes a domain the
moment the service starts, and this application is an archive of an entire organisation's mail, so
losing that race is not a small thing.

The wrapper closes the window:

1. Validate variables. Names, lengths and outcomes are printed; values never are.
2. Refuse configurations that would be unsafe or broken:
   - upstream's example `JWT_SECRET`, which would let anyone forge a session;
   - upstream's example `MEILI_MASTER_KEY` and `REDIS_PASSWORD`;
   - an `ENCRYPTION_KEY` that is not exactly 64 hex characters, since it protects the stored
     credentials of every mailbox connected to the archive;
   - an `APP_URL` that is not an absolute URL, which breaks CORS and the OAuth redirect;
   - ports that collide with each other.
3. Start the application with the frontend bound to loopback.
4. Wait for the API, then complete the setup through upstream's own endpoint. Idempotent: if setup
   is already done it says so and moves on, which is what makes changing your password in the app
   safe.
5. Wait for the frontend, then open the public listener.
6. Supervise both. If either exits the container exits; a signalled stop exits 0 so the platform
   does not record a crash.

Application code is untouched. The image adds Caddy, an entrypoint, a bootstrap script, the licence
files and OCI labels on top of the upstream image.

## Ports

| Port | Bound to | Purpose |
|---|---|---|
| `$PORT` (8080 by default) | all interfaces | Caddy, the only thing the outside world talks to |
| `3000` | 127.0.0.1 | SvelteKit frontend, which proxies `/api` to the API |
| `4000` | container network | Express API |

The frontend is a SvelteKit node adapter, so it reads `HOST` and `PORT`. Those are exactly the names
the platform uses for the public listener, so the entrypoint captures the public port first and then
rewrites `PORT` for the child process. Railway also probes its healthcheck against `PORT`, so the
public port, the domain target and the healthcheck all line up on one value.

## Start-up cost

The upstream image's entrypoint runs `pnpm install --frozen-lockfile --prod` and `pnpm db:migrate`
**on every container start**, not at build time. A cold start therefore downloads several hundred
packages and applies migrations before anything answers. The readiness timeout defaults to 900
seconds for that reason, and the healthcheck timeout in the template is generous to match.

## Health and readiness

The healthcheck is `GET /api/v1/auth/status` through the public port. It is unauthenticated by
design upstream and returns only `{"needsSetup":boolean}`. It passes only after Caddy is listening,
and Caddy starts only after setup is complete, so a passing healthcheck implies a claimed instance.

## Data

| What | Where |
|---|---|
| archived messages and attachments | `/var/data/open-archiver` on the `app` volume |
| users, roles, ingestion sources, job metadata | PostgreSQL |
| full-text index | Meilisearch, rebuildable from the archive |
| job queues | Valkey |

Set `STORAGE_ENCRYPTION_KEY` to encrypt archived files at rest. `STORAGE_TYPE=s3` moves the archive
to object storage instead, in which case the `app` volume only holds scratch data.
