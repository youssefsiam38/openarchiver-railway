# Security

## Reporting

Problems in **this wrapper** (entrypoint, bootstrap, template configuration): open an issue at
https://github.com/youssefsiam38/openarchiver-railway/issues. If the problem is exploitable, use
GitHub's private vulnerability reporting on that repository instead of a public issue.

Problems in **Open Archiver itself**: report upstream at
https://github.com/LogicLabs-OU/OpenArchiver/issues.

## What this deployment holds

An organisation's entire mail history, the attachments that came with it, and the stored credentials
or OAuth tokens for every mailbox it connects to. Treat it with the care that implies: it is a
higher-value target than the mail server it copies from, because it concentrates history that
individual mailboxes may have already deleted.

## First-run setup race

A fresh instance shows a setup page that creates the first Super Admin. Upstream refuses that page
once any account exists, which is correct, but the window between "service is reachable" and "you
reach the page" is a real one on a platform that publishes a domain immediately.

The wrapper completes the setup inside the container, against the API on loopback, before the public
listener is opened. The smoke test asserts that a later setup attempt is refused with 403 and leaves
no account behind.

The bootstrap is idempotent: once setup is complete it is never repeated, so
`OPENARCHIVER_ADMIN_PASSWORD` becomes a stale variable and changing your password in the app sticks.

## What is exposed

| Surface | Anonymous access |
|---|---|
| the web interface and the whole `/api/v1` surface | refused, HTTP 401 |
| `/api/v1/auth/setup` | refused, HTTP 403, because setup is already complete |
| `/api/v1/auth/status` | open; returns only `{"needsSetup":false}` |
| the frontend on port 3000 and the API on port 4000 | not published; only the proxy is reachable |
| PostgreSQL, Valkey, Meilisearch | Railway private network only |

## Placeholder values the wrapper refuses

Upstream's `.env.example` ships working placeholders. Deploying with them is the difference between
an archive only you can read and one anyone can mint a session for, so the wrapper refuses to start
on any of these:

| Variable | Refused value | What it would cost you |
|---|---|---|
| `JWT_SECRET` | `a-very-secret-key-that-you-should-change` | anyone can forge a Super Admin session |
| `MEILI_MASTER_KEY` | `aSampleMasterKey` | the search index is readable and writable |
| `REDIS_PASSWORD` | `defaultredispassword` | the job queues are readable and writable |

It also requires `ENCRYPTION_KEY` to be exactly 64 hex characters, because that key protects the
stored credentials of every connected mailbox, and a silently truncated one is worse than a missing
one.

## Secrets

- `OPENARCHIVER_ADMIN_PASSWORD`, `JWT_SECRET`, `ENCRYPTION_KEY`, `MEILI_MASTER_KEY` and the database
  and cache passwords are generated per deployment by the template.
- The wrapper prints variable **names**, lengths and outcomes — never values. The test suite asserts
  that the administrator password, the JWT secret and the encryption key never appear in the log.
- Rotating `ENCRYPTION_KEY` after mailboxes are connected makes their stored credentials unreadable;
  you have to reconnect each source.
- `STORAGE_ENCRYPTION_KEY` is optional and encrypts archived files at rest. Losing it loses the
  archive, so store it where you store your other recovery material.
- The values in `compose.yaml` are labelled local-test-only and exist so the suite can assert they
  never appear in logs. They are not secrets and must not be reused.

## Transport

Railway terminates TLS at the edge and forwards to Caddy, which proxies to the frontend over
loopback. The database, cache and search services speak plain protocols on the private network,
which is why none of them gets a public domain. `APP_URL` must be the `https://` public URL:
it sets the CORS origin and forms the OAuth redirect URI.

## Third-party calls made by the application

Connecting a mailbox means the archive talks to Google, Microsoft or your IMAP server with
credentials you supply. Nothing else leaves the deployment unless you configure it.

## Updates

Both base images are pinned by tag **and** digest; the workflow publishes multi-arch images and the
release notes record the digest. See [MAINTENANCE.md](MAINTENANCE.md).
