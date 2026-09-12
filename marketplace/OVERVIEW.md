# Deploy and Host Open Archiver on Railway

Open Archiver copies your organisation's mail out of Google Workspace, Microsoft 365, a generic IMAP
mailbox, or a PST, EML or mbox export, and keeps it in storage you control. Everything it archives
becomes full-text searchable, attachments included, and stays searchable after the original message
is deleted from the mailbox it came from. This is a community-maintained template; it is not
affiliated with the Open Archiver project.

## About Hosting Open Archiver

Open Archiver is a real platform rather than a single app, and hosting it reflects that. One
container runs the web interface, the API, and three background workers that ingest, index and
schedule. Around it sit a PostgreSQL database for metadata, a Valkey instance for the job queues, a
Meilisearch index for the search, and a volume for the archived mail itself. All four must agree on
connection strings and two shared keys.

The part that needs care is the first minute. A fresh instance shows a setup page that creates the
first Super Admin. The project closes that page correctly once an account exists, but on a hosting
platform the public address is live from the moment the service starts, and what sits behind that
page is an organisation's entire mail history. This template completes the setup inside the
container, before the public port is opened, so the instance is claimed before anybody can reach it.
It also refuses to start on the placeholder secrets shipped in the project's example configuration,
which are easy to copy and quiet when wrong.

Be aware of the cost. This is a four-service deployment, the application container idles at several
hundred megabytes before any mail is ingested, and the image reinstalls its dependencies on every
start, so deploys take minutes rather than seconds.

## Why Deploy Open Archiver on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your
infrastructure so you don't have to deal with configuration, while allowing you to vertically and
horizontally scale it.

By deploying Open Archiver on Railway, you are one step closer to supporting a complete full-stack
application with minimal burden. Host your servers, databases, AI agents, and more on Railway.

Concretely, this template provisions all four services, wires the connection strings and shared
keys, attaches the volumes, generates the administrator password and the encryption keys, creates
your account, and points the healthcheck at the one route that answers without a session.

## Common Use Cases

- Meet a mail retention obligation without paying per mailbox for a commercial archiving product.
- Keep a permanent, searchable record of correspondence after employees leave and their mailboxes
  are deleted.
- Load a decade of PST or mbox exports into one place and actually find things in them.
- Give auditors or legal a read-only account scoped to search rather than access to live mailboxes.

## Dependencies for Open Archiver Hosting

- A PostgreSQL database for users, roles, ingestion sources and job metadata.
- A Valkey or Redis instance for the ingestion and indexing queues.
- A Meilisearch instance for the full-text index.
- A persistent volume for the archived messages and attachments, or S3-compatible object storage.

### Deployment Dependencies

- Open Archiver upstream project and documentation: https://github.com/LogicLabs-OU/OpenArchiver
- Configuration reference: https://github.com/LogicLabs-OU/OpenArchiver/blob/main/.env.example
- Caddy, used as the gate that holds the public port shut until setup is complete: https://caddyserver.com
- Template repository, wrapper image and tests: https://github.com/youssefsiam38/openarchiver-railway
- Published image: `ghcr.io/youssefsiam38/openarchiver-railway`
- Open Archiver is licensed AGPL-3.0-only. Running it as a network service makes you a distributor
  under section 13, so keep the corresponding source of the version you run available.

### Implementation Details

The wrapper adds no application code. It validates the configuration and refuses the example secrets
and malformed keys, starts the application with its frontend on loopback, waits for the API, and
completes the setup through the application's own endpoint. Only then does it open the public port.
Completing the setup is idempotent, so a redeploy never disturbs an account whose password you have
since changed, and a signalled stop exits cleanly rather than looking like a crash.
