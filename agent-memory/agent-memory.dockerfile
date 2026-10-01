# syntax=docker/dockerfile:1
# The overlay: the agent-memory CLI and its setup script, staged under /out on
# the sandbox template (it has curl and sha256sum), then copied onto scratch
# so they land on whatever workload this mixin is composed with. The CLI is a
# static binary, so it needs nothing from that workload.
FROM docker/sandbox-templates:shell-docker AS build

ARG TARGETARCH
ARG AGENT_MEMORY_VERSION

# The pinned release from the same place `agent-memory upgrade` fetches it,
# checked against its published checksum and re-read so the kit cannot
# provide a version the overlay does not contain.
USER root
WORKDIR /tmp/agent-memory
RUN set -eux; \
    archive="agent-memory-v${AGENT_MEMORY_VERSION}.linux-${TARGETARCH}.tgz"; \
    base="https://download.surrealdb.com/agent-memory/v${AGENT_MEMORY_VERSION}"; \
    curl -fsSLO "$base/$archive"; \
    curl -fsSL "$base/$archive.sha256" | sha256sum -c -; \
    mkdir -p /out/usr/local/bin; \
    tar -xzf "$archive" --no-same-owner -C /out/usr/local/bin agent-memory; \
    /out/usr/local/bin/agent-memory --version | grep -qx "agent-memory ${AGENT_MEMORY_VERSION}"
COPY --chmod=0755 bin/ /out/usr/local/bin/

# The tarball carries the uid of the machine that packed it, and on an
# unknown base that uid may be a real account. Root owns the whole tree,
# /out included, since its metadata becomes the overlay's root. Nothing
# under /home ships, so the base's home directories stay as they are.
RUN chown -R 0:0 /out

FROM scratch
COPY --from=build /out /
