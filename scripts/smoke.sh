#!/usr/bin/env bash
# End-to-end check of the SurrealDB sandbox kit, driven from the host.
#
# Boots a throwaway sandbox from this kit and proves the whole chain works:
# the install step ran, SurrealDB started, the readiness gate held the shell
# back until it was serving, the root credentials authenticate, and a write
# followed by a read round-trips.
#
# Usage:
#   ./scripts/smoke.sh              # default in-memory storage
#   SURREAL_STORAGE=rocksdb ./scripts/smoke.sh
#
# Requires an authenticated sbx: run `sbx login` first.
set -euo pipefail

kit_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sandbox_name="${SBX_SMOKE_NAME:-surrealdb-smoke}"
storage="${SURREAL_STORAGE:-memory}"

cleanup() {
	echo "==> Removing sandbox '$sandbox_name'"
	sbx rm --force "$sandbox_name" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> Validating the kit"
sbx kit validate "$kit_dir"

cleanup

echo "==> Booting a sandbox from the kit (storage: $storage)"
# The agent script is single-quoted on purpose: $SURREAL_ENDPOINT and friends
# must expand inside the sandbox, not here on the host.
# shellcheck disable=SC2016
sbx run shell \
	--name "$sandbox_name" \
	--kit "$kit_dir" \
	-e "SURREAL_STORAGE=$storage" \
	-- -c '
    set -euo pipefail
    echo "--- surreal version ---"
    surreal version
    echo "--- readiness ---"
    surreal is-ready --endpoint "$SURREAL_ENDPOINT"
    echo "--- write ---"
    surreal sql --ns smoke --db smoke --json <<< "CREATE person:tobie SET name = \"Tobie\";"
    echo "--- read back ---"
    surreal sql --ns smoke --db smoke --json <<< "SELECT name FROM person:tobie;"
  '

echo "==> Smoke test passed"
