# Marketplace audit

Why this template was built, recorded at the time of publication.

## Gap

Searching the Railway marketplace returned nothing for email archiving:

| Query | Result |
|---|---|
| `open archiver` | no match |
| `email archive`, `archiving`, `journaling` | no match |
| `mailbox`, `imap` | no self-hosted archive |

The scan covered roughly seventy self-hosted applications. Most popular categories are already
served several times over; this one is empty.

## Why Open Archiver

- Actively maintained, tagged releases, official multi-arch images.
- AGPL-3.0: redistributable as long as the source offer is preserved, which the template documents.
- Answers a need with real deadlines behind it. Mail retention is a compliance obligation in a lot
  of places, and the commercial products that serve it are priced per mailbox.
- Ingests from Google Workspace, Microsoft 365, IMAP and PST/EML/mbox files, so it can archive what
  you have now and what you exported years ago.

## Why it needs a template rather than a raw image

- A fresh instance shows a setup page that mints the first Super Admin. Upstream closes it after the
  first account, but on a platform that publishes a domain immediately the race is real, and the
  prize is an organisation's whole mail history.
- Upstream's `.env.example` ships working placeholder values for `JWT_SECRET`, `MEILI_MASTER_KEY`
  and `REDIS_PASSWORD`. Copying them into a deployment is an easy and quiet mistake.
- `JWT_EXPIRES_IN` is required but has no default; without it the API dies with an empty error
  object that says nothing about the cause.
- Four services have to agree on connection strings and two shared keys.
- The frontend reads `HOST` and `PORT`, the same names the platform uses for the public listener.

The template answers all five without asking the deployer anything.

## Cost, stated plainly

This is the heaviest template in this family: four services, and an application container that idles
around 650 MB before any mail is ingested. It also re-installs its dependencies on every start, so
deploys take minutes. That is worth saying out loud in the listing rather than discovering after the
first bill.

## Category

Other — the marketplace has no compliance or archiving category; the template is a self-hosted data
platform with a web UI.
