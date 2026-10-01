#!/usr/bin/env bash
# Connect the agent to the Agent Memory context: its MCP server, and the
# hooks that recall and remember automatically. Run by the kit's lifecycle@1
# startup hook on every sandbox boot, so it must be idempotent.
#
# It fails open: memory that cannot be wired up must never stop the sandbox
# from booting, so every problem is reported and the script still exits 0.
set -uo pipefail

host="${1:?usage: agent-memory-setup.sh HOST}"
url="https://$host/mcp"
hook=/usr/local/bin/agent-memory-hook.sh

if [ -z "${SPECTRON_API_KEY:-}" ]; then
	echo "agent-memory: no API key bound for $host, so nothing is configured" >&2
	exit 0
fi

hooks=on
case "$(printf '%s' "${AGENT_MEMORY_HOOKS:-on}" | tr '[:upper:]' '[:lower:]')" in
0 | off | false | no) hooks=off ;;
esac

# set_hooks FILE STATUS: rewrite the hooks in a Claude Code or Codex hooks
# file — both use the same shape — dropping any of ours and, unless hooks are
# off, adding them back. STATUS is "yes" for the status line Codex shows while
# a hook runs. Hooks that are not ours are left alone. The definitions are
# byte-for-byte the same on every boot, which matters to Codex: it trusts a
# hook by the hash of its definition.
set_hooks() {
	local file="$1" status="$2" current next
	if ! command -v jq >/dev/null 2>&1; then
		echo "agent-memory: jq is missing, so automatic memory is not configured" >&2
		return 0
	fi
	current='{}'
	if [ -s "$file" ]; then
		if ! current="$(jq -e 'if type == "object" then . else error end' "$file" 2>/dev/null)"; then
			echo "agent-memory: $file is not a JSON object; leaving its hooks alone" >&2
			return 0
		fi
	fi
	next="$(jq --arg hook "$hook" --arg enabled "$hooks" --arg status "$status" '
		def entry($mode; $timeout; $message):
			{hooks: [{type: "command", command: ($hook + " " + $mode), timeout: $timeout}
				+ (if $status == "yes" then {statusMessage: $message} else {} end)]};
		.hooks = ((.hooks // {})
			| with_entries(.value |= map(select(
				[(.hooks // [])[] | .command // "" | startswith($hook)] | any | not)))
			| with_entries(select(.value | length > 0)))
		| if $enabled == "on" then
			.hooks.SessionStart += [entry("recall"; 12; "Recalling from Agent Memory")]
			| .hooks.UserPromptSubmit += [entry("recall"; 12; "Recalling from Agent Memory")]
			| .hooks.Stop += [entry("remember"; 15; "Saving to Agent Memory")]
		  else . end
		| if .hooks == {} then del(.hooks) else . end' <<<"$current")" || return 0
	mkdir -p "$(dirname "$file")"
	printf '%s\n' "$next" >"$file.agent-memory.tmp" && mv "$file.agent-memory.tmp" "$file"
}

# SPECTRON_API_KEY holds the sandbox's placeholder, never the key itself: the
# proxy swaps the real key in on requests to $host. Writing it into the
# agent's configuration therefore writes nothing secret.

if command -v claude >/dev/null 2>&1; then
	claude mcp remove --scope user agent-memory >/dev/null 2>&1 || true
	if claude mcp add --scope user --transport http agent-memory "$url" \
		--header "Authorization: Bearer $SPECTRON_API_KEY" >/dev/null; then
		echo "agent-memory: Claude Code uses $url" >&2
	else
		echo "agent-memory: could not add the MCP server to Claude Code" >&2
	fi
	set_hooks "$HOME/.claude/settings.json" no
	echo "agent-memory: Claude Code automatic memory is $hooks" >&2
fi

# Codex reads the key from the environment each time it connects. It runs
# hooks from its user configuration only once someone has trusted them in
# /hooks; until then it skips them and says so at startup.
if command -v codex >/dev/null 2>&1; then
	codex mcp remove agent-memory >/dev/null 2>&1 || true
	if codex mcp add agent-memory --url "$url" \
		--bearer-token-env-var SPECTRON_API_KEY >/dev/null; then
		echo "agent-memory: Codex uses $url" >&2
	else
		echo "agent-memory: could not add the MCP server to Codex" >&2
	fi
	set_hooks "$HOME/.codex/hooks.json" yes
	echo "agent-memory: Codex automatic memory is $hooks (trust it once in /hooks)" >&2
fi

exit 0
