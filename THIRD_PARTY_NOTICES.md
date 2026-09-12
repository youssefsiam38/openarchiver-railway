# Third-party notices

This template deploys software written by other people. Their licences apply to what runs; the
wrapper code in this repository is MIT.

## Shipped inside the wrapper image

| Component | Version | Licence | Source |
|---|---|---|---|
| Open Archiver | 0.6.0 | AGPL-3.0-only | https://github.com/LogicLabs-OU/OpenArchiver/tree/v0.6.0 |
| Caddy | 2.10.2 | Apache-2.0 | https://github.com/caddyserver/caddy |

The licence texts are in [`licenses/`](licenses) and inside the image at
`/usr/share/licenses/openarchiver-railway/`.

Open Archiver bundles its own npm dependencies (SvelteKit, Express, Drizzle, BullMQ and others)
under their respective licences; they are unchanged from the upstream image and their metadata ships
with it. Caddy is distributed as a single static binary that embeds its own Go dependencies,
likewise unchanged.

## Deployed alongside, as their own services

| Component | Version | Licence | Source |
|---|---|---|---|
| PostgreSQL | Railway managed | PostgreSQL Licence | https://www.postgresql.org |
| Valkey | 8 | BSD-3-Clause | https://github.com/valkey-io/valkey |
| Meilisearch | v1.38 | MIT | https://github.com/meilisearch/meilisearch |

These images are pulled from their publishers at deploy time and are not redistributed by this
repository.

## AGPL §13

If other people use your deployment over a network, you must be able to offer them the corresponding
source of the version you run. The exact upstream tag is recorded above, in the image label
`io.openarchiver-railway.upstream.version`, and in [UPSTREAM.md](UPSTREAM.md).

## Trademarks and artwork

The marketplace card uses Open Archiver's own icon; see [`assets/README.md`](assets/README.md). This
template is not affiliated with, endorsed by, or supported by the Open Archiver project.

## This repository

MIT — see [LICENSE](LICENSE). It contains no upstream source code.
