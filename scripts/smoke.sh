#!/usr/bin/env bash
# End-to-end check of both SurrealDB sandbox kits, driven from the host.
#
# Boots throwaway sandboxes from the surrealdb workload and from the
# surrealdb-mixin composed onto a v3 shell workload, and proves the whole chain
# works in each: the pinned binary is in the image, the startup hooks started
# SurrealDB, the root credentials authenticate, and a write followed by a read
# round-trips. Under rocksdb it also stops and restarts each sandbox before
# reading back, which proves the volume, its ownership, and that the hooks run
# again on every boot.
#
# Usage:
#   ./scripts/smoke.sh              # default in-memory storage
#   SURREAL_STORAGE=rocksdb ./scripts/smoke.sh
#
# Requires an authenticated sbx: run `sbx login` first. sbx builds the kits
# from source, which needs a buildx builder that can export OCI images (see
# Development in the README).
set -euo pipefail

kit_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sandbox_name="${SBX_SMOKE_NAME:-surrealdb-smoke}"
storage="${SURREAL_STORAGE:-memory}"
# The v3 workload the mixin is composed onto. v3 mixins cannot compose with
# the built-in (v2) agents, so this is a published v3 kit.
mixin_base="${SBX_SMOKE_MIXIN_BASE:-docker/sbx-kit-shell:1.0.0}"

workload="$sandbox_name"
mixin="$sandbox_name-mixin"

cleanup() {
	for name in "$workload" "$mixin"; do
		sbx rm --force "$name" >/dev/null 2>&1 || true
	done
}
trap 'echo "==> Removing sandboxes"; cleanup' EXIT

# The scripts below are single-quoted on purpose: $SURREAL_ENDPOINT and friends
# must expand inside the sandbox, not here on the host. They run from $HOME
# because `surreal sql` writes its history.txt to the working directory, which
# is otherwise this repository, mounted as the workspace.
# shellcheck disable=SC2016
write='
  set -euo pipefail
  cd "$HOME"
  echo "--- surreal version ---"
  surreal version
  echo "--- readiness ---"
  surreal is-ready --endpoint "$SURREAL_ENDPOINT"
  echo "--- write ---"
  surreal sql --hide-welcome --ns smoke --db smoke --json <<< "CREATE person:tobie SET name = \"Tobie\";"
'
# shellcheck disable=SC2016
read_back='
  set -euo pipefail
  cd "$HOME"
  echo "--- read back ---"
  out="$(surreal sql --hide-welcome --ns smoke --db smoke --json <<< "SELECT name FROM person:tobie;")"
  echo "$out"
  grep -q Tobie <<< "$out"
'

# check NAME: round-trip a record in the sandbox, then under rocksdb read it
# back again after a stop and start.
check() {
	sbx exec "$1" bash -c "$write"
	sbx exec "$1" bash -c "$read_back"
	if [ "$storage" = rocksdb ]; then
		echo "--- restart ---"
		sbx stop "$1"
		sbx exec "$1" /usr/local/bin/surrealdb-wait.sh
		sbx exec "$1" bash -c "$read_back"
	fi
}

echo "==> Inspecting the kits"
sbx kit inspect "$kit_dir/surrealdb"
sbx kit inspect "$kit_dir/surrealdb-mixin"

cleanup

echo "==> Booting the surrealdb workload (storage: $storage)"
sbx run --detached --name "$workload" -e "SURREAL_STORAGE=$storage" "$kit_dir/surrealdb"
check "$workload"

echo "==> Booting $mixin_base with the surrealdb-mixin (storage: $storage)"
sbx run --detached --name "$mixin" -e "SURREAL_STORAGE=$storage" \
	--kit "$kit_dir/surrealdb-mixin" "$mixin_base"
check "$mixin"
sbx exec "$mixin" test -f /usr/share/sandbox/kit/surrealdb-mixin/surrealdb-context.md

echo "==> Smoke test passed"
