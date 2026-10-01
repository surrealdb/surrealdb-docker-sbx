#!/usr/bin/env bash
# Block until SurrealDB accepts connections, so the shell never hands over to a
# user in front of a database that is not up yet. Run by the kit's lifecycle@1
# startup hook, in the foreground, right after surrealdb-start.sh.
#
# Kept byte-identical in surrealdb/bin/ and surrealdb-mixin/bin/ (CI enforces
# it): a kit's build context is its own directory, so the two kits cannot
# share one copy.
set -euo pipefail

endpoint="${SURREAL_ENDPOINT:-http://127.0.0.1:8000}"
attempts="${SURREAL_WAIT_ATTEMPTS:-60}"

for _ in $(seq 1 "$attempts"); do
	if surreal is-ready --endpoint "$endpoint" >/dev/null 2>&1; then
		echo "surrealdb: ready at $endpoint" >&2
		exit 0
	fi
	sleep 0.5
done

echo "surrealdb: not ready at $endpoint after $attempts attempts" >&2
exit 1
