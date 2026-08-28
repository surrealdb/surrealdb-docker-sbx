#!/usr/bin/env bash
# Start SurrealDB inside the sandbox. Run by the kit's setup.startup hook on
# every sandbox start, so it must be idempotent.
set -euo pipefail

# Already serving? Nothing to do.
if pgrep -x surreal >/dev/null 2>&1; then
	echo "surrealdb: already running" >&2
	exit 0
fi

# SURREAL_STORAGE is the friendly switch; SURREAL_PATH is the escape hatch for
# any backend the CLI understands (tikv://, surrealkv://, ...). An explicit
# SURREAL_PATH always wins.
storage="${SURREAL_STORAGE:-memory}"
data_dir="${SURREAL_DATA_DIR:-$HOME/.surrealdb/data}"

if [ -z "${SURREAL_PATH:-}" ]; then
	case "$storage" in
	memory)
		SURREAL_PATH="memory"
		;;
	rocksdb)
		mkdir -p "$data_dir"
		SURREAL_PATH="rocksdb:$data_dir"
		;;
	*)
		echo "surrealdb: unknown SURREAL_STORAGE=$storage (expected 'memory' or 'rocksdb')" >&2
		exit 1
		;;
	esac
	export SURREAL_PATH
fi

echo "surrealdb: starting on ${SURREAL_BIND:-127.0.0.1:8000} (path: $SURREAL_PATH)" >&2

# --bind, --user and --pass are all read from the environment (SURREAL_BIND,
# SURREAL_USER, SURREAL_PASS), which the kit sets.
exec surreal start --no-banner
