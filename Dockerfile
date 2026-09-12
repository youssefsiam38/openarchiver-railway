# syntax=docker/dockerfile:1
#
# openarchiver-railway: thin wrapper around the official Open Archiver image.
#
# Open Archiver closes its own setup endpoint once the first user exists, which is the right
# behaviour, but it still means whoever reaches a fresh deployment first becomes Super Admin of an
# archive holding an entire organisation's mail. On Railway the public domain exists from the first
# second, so this wrapper runs the app on loopback, completes that setup itself, and only then opens
# the public port. Application code is unchanged.
#
# Both images are pinned by tag AND digest. Update the image and version args together.
ARG CADDY_IMAGE=docker.io/library/caddy:2.10-alpine@sha256:4c6e91c6ed0e2fa03efd5b44747b625fec79bc9cd06ac5235a779726618e530d
ARG OPENARCHIVER_IMAGE=docker.io/logiclabshq/open-archiver:v0.6.0@sha256:3c240bf852d604b73a5229c0a22e2e69987e8e9cfe7241710598ca6187c08b83

FROM ${CADDY_IMAGE} AS caddy

FROM ${OPENARCHIVER_IMAGE}

ARG OPENARCHIVER_VERSION=0.6.0
ARG CADDY_VERSION=2.10.2
ARG WRAPPER_VERSION=0.0.0-dev
ARG VCS_REF=unknown
ARG BUILD_DATE=1970-01-01T00:00:00Z

USER root

# Caddy ships as a static Go binary, so the alpine-built one runs here unchanged.
COPY --from=caddy /usr/bin/caddy /usr/local/bin/caddy
COPY licenses/ /usr/share/licenses/openarchiver-railway/
COPY --chmod=0755 scripts/entrypoint.sh /usr/local/bin/openarchiver-railway-entrypoint
COPY scripts/bootstrap-admin.mjs /usr/local/lib/openarchiver-railway/bootstrap-admin.mjs
RUN caddy version \
    && chmod 755 /usr/local/lib/openarchiver-railway \
    && chmod 644 /usr/local/lib/openarchiver-railway/bootstrap-admin.mjs \
    && node --check /usr/local/lib/openarchiver-railway/bootstrap-admin.mjs \
    && mkdir -p /etc/openarchiver-railway

# The frontend listens on loopback; Caddy holds the public port. PORT_BACKEND stays internal either
# way -- only the frontend is ever reachable, and it proxies /api itself.
ENV HOST=127.0.0.1 \
    PORT=8080 \
    OPENARCHIVER_INTERNAL_PORT=3000 \
    PORT_BACKEND=4000 \
    JWT_EXPIRES_IN=7d \
    STORAGE_TYPE=local \
    STORAGE_LOCAL_ROOT_PATH=/var/data/open-archiver \
    NODE_ENV=production

LABEL org.opencontainers.image.title="openarchiver-railway" \
      org.opencontainers.image.description="Community Railway wrapper for Open Archiver, the email archiving platform. Claims the setup page before anyone else can. Not affiliated with the Open Archiver project." \
      org.opencontainers.image.source="https://github.com/youssefsiam38/openarchiver-railway" \
      org.opencontainers.image.url="https://github.com/youssefsiam38/openarchiver-railway" \
      org.opencontainers.image.documentation="https://github.com/youssefsiam38/openarchiver-railway#readme" \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.version="${WRAPPER_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.base.name="docker.io/logiclabshq/open-archiver:${OPENARCHIVER_VERSION}" \
      io.openarchiver-railway.upstream.version="${OPENARCHIVER_VERSION}" \
      io.openarchiver-railway.caddy.version="${CADDY_VERSION}"

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/openarchiver-railway-entrypoint"]
