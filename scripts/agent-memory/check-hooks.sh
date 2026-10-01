#!/usr/bin/env bash
# Check the agent-memory kit's automatic memory hooks. Runs inside a sandbox
# the kit is composed into; smoke-agent-memory.sh copies it in with
# mock-mcp.py beside it, and passes the agent the sandbox runs.
#
# The hooks talk to mock-mcp.py rather than the context — SPECTRON_URL points
# them there — so nothing is stored, and the checks need no Agent Memory
# context and no agent login: the agent's own model call may fail, and its
# SessionStart and UserPromptSubmit hooks still fire before it does.
#
# Usage: check-hooks.sh claude|codex
set -euo pipefail

agent="${1:?usage: check-hooks.sh claude|codex}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hook=/usr/local/bin/agent-memory-hook.sh
log=/tmp/agent-memory-hooks.log
port=8765
cd /tmp

: >"$log"
setsid nohup python3 "$here/mock-mcp.py" "$port" "$log" >/dev/null 2>&1 </dev/null &
for _ in $(seq 1 20); do
	curl -s -o /dev/null -X POST -d '{}' "http://127.0.0.1:$port" && break
	sleep 0.25
done
: >"$log"
export SPECTRON_URL="http://127.0.0.1:$port"

echo "--- hooks registered ---"
case "$agent" in
claude) config="$HOME/.claude/settings.json" ;;
codex) config="$HOME/.codex/hooks.json" ;;
esac
test "$(jq --arg hook "$hook" '[.hooks[][] | .hooks[].command | select(startswith($hook))] | length' "$config")" = 3

echo "--- recall puts memories into the agent's context ---"
out="$(echo '{"hook_event_name":"UserPromptSubmit","session_id":"smoke","prompt":"how do we deploy?"}' | "$hook" recall)"
jq -e '.hookSpecificOutput.additionalContext | contains("make release")' <<<"$out" >/dev/null

echo "--- remember stores the exchange ---"
echo '{"hook_event_name":"Stop","session_id":"smoke","last_assistant_message":"Run make release."}' | "$hook" remember
tail -n 1 "$log" | jq -e '.body.params.arguments.text == "User: how do we deploy?\n\nAssistant: Run make release."' >/dev/null

echo "--- the hooks fail open when memory is unreachable ---"
test -z "$(echo '{"hook_event_name":"SessionStart","session_id":"down"}' | SPECTRON_URL=http://127.0.0.1:9 "$hook" recall)"

echo "--- $agent fires them ---"
: >"$log"
case "$agent" in
claude) timeout 90 claude -p "smoke test" </dev/null >/dev/null 2>&1 || true ;;
# Codex runs user hooks once they are trusted in /hooks; a smoke test has no
# one to trust them, so it bypasses the check for this one invocation.
codex) timeout 90 codex exec --skip-git-repo-check --dangerously-bypass-hook-trust "smoke test" </dev/null >/dev/null 2>&1 || true ;;
esac
test "$(jq -s 'map(select(.body.params.name == "recall")) | length' "$log")" -ge 2
