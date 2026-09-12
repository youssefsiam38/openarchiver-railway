# Maintenance

## Release process

1. Update a pinned image (see [UPSTREAM.md](UPSTREAM.md)) or the wrapper scripts.
2. Run the full local suite. It is slow: the image installs dependencies on every container start,
   and the suite starts the stack three times.
   ```bash
   tests/static.sh && docker compose build && tests/smoke.sh && tests/persistence.sh
   ```
3. Commit on `main`. CI (`test.yml`) runs the same suite on every push and pull request.
4. Tag and push:
   ```bash
   git tag -a vX.Y.Z -m "openarchiver-railway vX.Y.Z" && git push origin vX.Y.Z
   ```
   `publish-image.yml` builds an amd64 candidate, runs the suite against **that** image, and only
   then pushes the multi-arch image to `ghcr.io/youssefsiam38/openarchiver-railway:X.Y.Z`.
5. Note the digest from the workflow summary.
6. Point the template at the new tag:
   ```bash
   npx -y @railway/cli@latest templates update open-archiver --readme-file marketplace/OVERVIEW.md
   ```
   or patch the service image through the template editor. Railway's template generator rejects
   `@sha256:` references, so templates use the version tag; the tag is immutable in practice because
   releases never re-push an existing tag. The marketplace overview lives in
   `marketplace/OVERVIEW.md`; Railway validates its section headings, so keep them.
7. Write release notes recording the wrapper version, the upstream version and the image digest.

## What to watch

| Thing | Where | Why |
|---|---|---|
| Open Archiver releases | https://github.com/LogicLabs-OU/OpenArchiver/releases | schema migrations, new required variables |
| `.env.example` upstream | the repository root | required variables appear there first; `JWT_EXPIRES_IN` is one the app refuses to start without |
| the setup endpoint | `packages/backend/src/api/routes/auth.routes.ts` | the bootstrap depends on its status and response codes |
| Meilisearch major versions | https://github.com/meilisearch/meilisearch/releases | index format changes need a re-index |
| Railway template deploys | Railway dashboard | deploy failures show up as template health |

## Breaking-change checklist

Before releasing an upstream bump:

- [ ] Does `GET /v1/auth/status` still return `{"needsSetup":boolean}`? The bootstrap reads it.
- [ ] Does `POST /v1/auth/setup` still return 201 once and 403 afterwards?
- [ ] Does the frontend still proxy `/api/v1/*` to the API, and still read `HOST` and `PORT`?
- [ ] Are there new required variables? The app throws a bare `error: {}` when one is missing, which
      is very hard to diagnose; add it to the entrypoint's validation with a readable message.
- [ ] Does the search endpoint still take `keywords`? It answers 400 without it.
- [ ] Does the release change the entrypoint's install-on-start behaviour? If it moves to build
      time, lower `APP_READY_TIMEOUT` and the template's healthcheck timeout.
- [ ] `tests/railway-smoke.sh` green against a staging deploy, including the persistence run with
      `STATE_OUT` / `STATE_IN` across a redeploy.

## Rolling back

Templates pin a version tag, so a bad release is undone by pointing the template back at the
previous tag and redeploying. Data lives in the volumes and in PostgreSQL and is untouched by an
image rollback, provided the newer version did not migrate the schema forward.

## If this repository is abandoned

The template is a thin wrapper: fork it, change the GHCR path in the workflow and the template, and
publish your own. Nothing here depends on this account.
