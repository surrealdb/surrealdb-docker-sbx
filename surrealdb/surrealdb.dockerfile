# syntax=docker/dockerfile:1
# The shell-docker template carries the platform floor (bash, the agent user,
# git, a CA store) plus a Docker engine — the same base the v2 kit ran on.
FROM docker/sandbox-templates:shell-docker

ARG TARGETARCH
ARG SURREAL_VERSION

# The pinned release, from the same place install.surrealdb.com downloads it.
# The tarball carries the uid of the machine that packed it, so ownership is
# not preserved; and the version is re-read so the kit cannot provide a
# version the image does not contain.
USER root
RUN set -eux; \
    curl -fsSL "https://download.surrealdb.com/v${SURREAL_VERSION}/surreal-v${SURREAL_VERSION}.linux-${TARGETARCH}.tgz" \
      | tar -xz --no-same-owner -C /usr/local/bin surreal; \
    surreal version | grep -qE "^${SURREAL_VERSION}[+ ]"
COPY --chmod=0755 bin/ /usr/local/bin/
USER agent

# Read by `surreal start` for the listen address. Bound to all interfaces so
# the published port reaches it; the microVM is the isolation boundary.
ENV SURREAL_BIND="0.0.0.0:8000"
# Read by both `surreal start` (to seed the root user) and by client commands
# such as `surreal sql`, so the CLI needs no credential flags.
ENV SURREAL_USER="root"
ENV SURREAL_PASS="root"
# Consumed by surrealdb-wait.sh and by anything you write against the DB.
ENV SURREAL_ENDPOINT="http://127.0.0.1:8000"
# Friendly storage switch: memory | rocksdb. See surrealdb-start.sh.
ENV SURREAL_STORAGE="memory"

# The template's entrypoint is `tini -- bash`; the sandbox runs a login shell.
ENTRYPOINT ["bash"]
CMD ["-l"]
