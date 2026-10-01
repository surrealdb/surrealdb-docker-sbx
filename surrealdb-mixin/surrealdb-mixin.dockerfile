# syntax=docker/dockerfile:1
# The overlay: the surreal binary and the two startup scripts, staged under
# /out on the same template the surrealdb workload runs on (it has curl, and
# the glibc the version check needs), then copied onto scratch so they land
# on whatever workload this mixin is composed with.
FROM docker/sandbox-templates:shell-docker AS build

ARG TARGETARCH
ARG SURREAL_VERSION

# The pinned release, from the same place install.surrealdb.com downloads it,
# re-read so the kit cannot provide a version the overlay does not contain.
USER root
RUN set -eux; \
    mkdir -p /out/usr/local/bin; \
    curl -fsSL "https://download.surrealdb.com/v${SURREAL_VERSION}/surreal-v${SURREAL_VERSION}.linux-${TARGETARCH}.tgz" \
      | tar -xz --no-same-owner -C /out/usr/local/bin surreal; \
    /out/usr/local/bin/surreal version | grep -qE "^${SURREAL_VERSION}[+ ]"
COPY --chmod=0755 bin/ /out/usr/local/bin/

# The tarball carries the uid of the machine that packed it, and on an
# unknown base that uid may be a real account. Root owns the whole tree,
# /out included, since its metadata becomes the overlay's root. Nothing
# under /home ships, so the base's home directories stay as they are.
RUN chown -R 0:0 /out

FROM scratch
COPY --from=build /out /

# Env is additive at assembly, so these reach the composed sandbox — and the
# agent, which reads the image environment rather than a profile script.
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
