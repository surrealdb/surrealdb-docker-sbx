#!/usr/bin/env bash
# End-to-end check of the agent-memory kit, driven from the host.
#
# Composes the kit onto v3 shell, Claude Code and Codex workloads and proves
# the chain in each: the pinned CLI is in the image, its profile points at the
# context, the context host is reachable and nothing else is, the API key is a
# placeholder inside the sandbox, and the agent's MCP client is wired to the
# context's /mcp endpoint. For Claude Code and Codex it also checks the
# automatic memory hooks against a stand-in /mcp server inside the sandbox
# (agent-memory/check-hooks.sh), including that the agent itself fires them.
#
# Two modes, chosen by AGENT_MEMORY_HOST:
#
#   stand-in (default)  httpbin.org plays the context host. It echoes request
#                       headers, which proves the proxy presents the real key;
#                       it cannot answer as Agent Memory, so nothing is stored.
#   live                your context. Adds a remember → recall round trip
#                       through the CLI, the recall hook and an MCP
#                       tools/list, then forgets what it stored.
#
# Usage:
#   ./scripts/smoke-agent-memory.sh
#   AGENT_MEMORY_HOST=abc123.spectron.cloud AGENT_MEMORY_CONTEXT_ID=ctx_123 \
#     ./scripts/smoke-agent-memory.sh
#
# Requires an authenticated sbx and, for either mode, the kit's credential
# stored and bound for the host — see agent-memory/README.md. In stand-in mode
# set AGENT_MEMORY_EXPECT_KEY to the stored value to assert it is the one the
# host receives. sbx builds the kit from source; see Development in the README
# for the buildx builder that needs.
set -euo pipefail

kit_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/agent-memory"
checks_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/agent-memory"
sandbox_name="${SBX_SMOKE_NAME:-agent-memory-smoke}"
host="${AGENT_MEMORY_HOST:-httpbin.org}"
context_id="${AGENT_MEMORY_CONTEXT_ID:-smoke}"
# Published v3 workloads. v3 mixins cannot compose with the built-in (v2)
# agents, and these tags are ones sbx 0.46 can load.
shell_base="${SBX_SMOKE_SHELL_BASE:-docker/sbx-kit-shell:1.0.0}"
claude_base="${SBX_SMOKE_CLAUDE_BASE:-docker/sbx-kit-claude:2.1.278}"
codex_base="${SBX_SMOKE_CODEX_BASE:-docker/sbx-kit-codex:0.159.2}"

live=false
[ "$host" != httpbin.org ] && live=true

cleanup() {
	for agent in shell claude codex; do
		sbx rm --force "$sandbox_name-$agent" >/dev/null 2>&1 || true
	done
}
trap 'echo "==> Removing sandboxes"; cleanup' EXIT

# boot AGENT BASE: create a detached sandbox with the kit composed onto BASE.
boot() {
	echo "==> Booting $2 with agent-memory (host: $host)"
	sbx run --detached --name "$sandbox_name-$1" \
		--kit "$kit_dir" --kit-arg "host=$host" --kit-arg "contextId=$context_id" "$2"
}

# check_hooks AGENT: run agent-memory/check-hooks.sh in that agent's sandbox.
check_hooks() {
	local name="$sandbox_name-$1" file
	for file in mock-mcp.py check-hooks.sh; do
		sbx exec -i "$name" bash -c "mkdir -p /tmp/agent-memory-checks && cat > /tmp/agent-memory-checks/$file" \
			<"$checks_dir/$file"
	done
	sbx exec "$name" bash /tmp/agent-memory-checks/check-hooks.sh "$1"
}

# The scripts below are single-quoted on purpose: their variables expand inside
# the sandbox, where the host and the expected key are passed as arguments.
# shellcheck disable=SC2016
common='
  set -euo pipefail
  host="$1"
  echo "--- agent-memory version ---"
  agent-memory --version
  echo "--- profile ---"
  grep -qx "url = \"https://$host\"" ~/.config/spectron/config.toml
  test "$(stat -c %U:%a ~/.config/spectron/config.toml)" = agent:600
  echo "--- key is a placeholder ---"
  test -n "${SPECTRON_API_KEY:-}"
  echo "--- egress: everything but the context host refused ---"
  test "$(curl -s -o /dev/null -w "%{http_code}" --max-time 20 https://example.com)" = 403
  test "$(curl -s -o /dev/null -w "%{http_code}" --max-time 20 https://download.surrealdb.com/agent-memory/latest.txt)" = 403
'

# shellcheck disable=SC2016
stand_in='
  set -euo pipefail
  expected="$1"
  echo "--- the host receives the stored key, not the placeholder ---"
  got="$(curl -sS --max-time 20 https://httpbin.org/anything -H "Authorization: Bearer $SPECTRON_API_KEY" | jq -r .headers.Authorization)"
  test "$got" != "Bearer $SPECTRON_API_KEY"
  if [ -n "$expected" ]; then
    test "$got" = "Bearer $expected"
    if env | grep -qF -- "$expected"; then
      echo "the real key is in the sandbox environment" >&2
      exit 1
    fi
  fi
'

# shellcheck disable=SC2016
live_round_trip='
  set -euo pipefail
  cd "$HOME"
  marker="sbx-smoke-$(date +%s)-$RANDOM"
  echo "--- MCP tools/list ---"
  curl -sS --max-time 30 -X POST "https://$1/mcp" \
    -H "Authorization: Bearer $SPECTRON_API_KEY" -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}" | grep -q "\"recall\""
  echo "--- remember, then recall ---"
  agent-memory remember "The Docker Sandboxes smoke test marker is $marker."
  for _ in $(seq 1 12); do
    if agent-memory recall "Docker Sandboxes smoke test marker" | grep -q "$marker"; then
      found=1; break
    fi
    sleep 5
  done
  echo "--- the recall hook finds it too ---"
  hooked="$(printf "%s" "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$marker\",\"prompt\":\"Docker Sandboxes smoke test marker\"}" \
    | /usr/local/bin/agent-memory-hook.sh recall)"
  agent-memory forget "Docker Sandboxes smoke test marker $marker" >/dev/null || true
  test "${found:-0}" = 1
  grep -q "$marker" <<<"$hooked"
'

echo "==> Inspecting the kit"
sbx kit inspect --kit-arg "host=$host" --kit-arg "contextId=$context_id" "$kit_dir"

cleanup

boot shell "$shell_base"
sbx exec "$sandbox_name-shell" bash -c "$common" _ "$host"
if $live; then
	sbx exec "$sandbox_name-shell" bash -c "$live_round_trip" _ "$host"
else
	sbx exec "$sandbox_name-shell" bash -c "$stand_in" _ "${AGENT_MEMORY_EXPECT_KEY:-}"
fi

boot claude "$claude_base"
sbx exec "$sandbox_name-claude" bash -c "$common" _ "$host"
echo "--- Claude Code MCP ---"
out="$(sbx exec "$sandbox_name-claude" claude mcp get agent-memory)"
grep -q "URL: https://$host/mcp" <<<"$out"
if $live; then grep -q "Connected" <<<"$out"; fi
check_hooks claude

boot codex "$codex_base"
sbx exec "$sandbox_name-codex" bash -c "$common" _ "$host"
echo "--- Codex MCP ---"
sbx exec "$sandbox_name-codex" codex mcp list | grep -E "^agent-memory +https://$host/mcp +SPECTRON_API_KEY"
check_hooks codex

echo "==> Agent Memory smoke test passed ($($live && echo live || echo stand-in))"
