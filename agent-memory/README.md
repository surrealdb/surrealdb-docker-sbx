# SurrealDB Agent Memory kit

A [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) mixin that gives a coding agent
persistent memory backed by [SurrealDB Agent Memory](https://surrealdb.com/docs/agent-memory).

Sandboxes are disposable; this memory is not. It lives in your Agent Memory context rather than
in the microVM, so what the agent remembers in one sandbox it can recall in the next — or in a
sandbox running a different agent.

The kit adds:

- the `agent-memory` CLI, pinned and checksum-verified, configured for your context;
- the context's MCP server, registered as `agent-memory` in Claude Code and Codex;
- [automatic memory](#automatic-memory) in Claude Code and Codex: relevant memories recalled into
  the agent's context as it starts and with every prompt, and every finished exchange stored;
- instructions telling the agent when to recall and what to remember;
- a network policy that allows your context host and nothing else.

Your API key never enters the sandbox. The sandbox holds a placeholder, and the sandbox proxy
presents the real key on requests to your context host, and only there.

## Before you start

You need an Agent Memory context. In [SurrealDB Studio](https://studio.surrealdb.com), open your
organisation → **Contexts**, open the context → **API keys**, and note three things:

- the **host**, such as `abc123.spectron.cloud` — without `https://`;
- the **context id**;
- an **API key** (`sk-ctx-…`), shown once when you create it.

Then store the key on your host, under the service name this kit asks for:

```bash
sbx secret set agent-memory
```

## Usage

Compose the kit onto a v3 agent workload, passing your host and context id:

```bash
sbx run docker/sbx-kit-claude:2.1.278 \
  --kit 'git+https://github.com/surrealdb-dev/surrealdb-docker-sbx.git#dir=agent-memory' \
  --kit-arg host=abc123.spectron.cloud \
  --kit-arg contextId=<your-context-id>
```

The first time, `sbx` asks you to approve the kit's use of your `agent-memory` secret on that
host. Codex works the same way with `docker/sbx-kit-codex`, with one more step: run `/hooks` in
your first Codex session and trust the three Agent Memory hooks (see
[Automatic memory](#automatic-memory)). Any other v3 workload gets the CLI and the instructions,
and `agent-memory mcp` prints a config snippet for its MCP client.

From a local clone, point `--kit` at the directory instead: `--kit ./agent-memory`.

v3 mixins compose onto v3 workloads only — the `docker` organisation's `sbx-kit-*` kits on
[Docker Hub](https://hub.docker.com/search?type=sbx_kit&badges=verified_publisher). The built-in
agent names (`sbx run claude`) are still v2 and cannot take it.

### With SurrealDB too

The kit composes alongside the [`surrealdb-mixin`](../surrealdb-mixin/), giving the agent both a
database to work against and a memory. With more than one kit, name the kit an argument is for:

```bash
sbx run docker/sbx-kit-claude:2.1.278 \
  --kit 'git+https://github.com/surrealdb-dev/surrealdb-docker-sbx.git#dir=surrealdb-mixin' \
  --kit 'git+https://github.com/surrealdb-dev/surrealdb-docker-sbx.git#dir=agent-memory' \
  --kit-arg agent-memory.host=abc123.spectron.cloud \
  --kit-arg agent-memory.contextId=<your-context-id>
```

To stop retyping the two values, put them in a file and pass `--kit-args-file`:

```
agent-memory.host=abc123.spectron.cloud
agent-memory.contextId=<your-context-id>
```

### Unattended runs

`sbx run --detached` and CI cannot prompt for the approval, and start the sandbox **without** the
key when there is none. Approve once interactively, or add the binding to
`~/.config/sbx/credentials.yaml` yourself:

```yaml
bindings:
  agent-memory:
    apiKey:
      domains: [abc123.spectron.cloud]
```

Without the key, the sandbox still boots and the MCP server is still registered; calls to the
context return `401`, and the agent is told to report that rather than retry.

### Rotating the key

`sbx secret set agent-memory` asks before overwriting a stored key; answer `y`, or remove the old
one first with `sbx secret rm agent-memory -f`. Running sandboxes pick up the new key.

## Automatic memory

In Claude Code and Codex the kit registers three lifecycle hooks, so memory works without the
agent having to ask:

| Event | Hook does |
| --- | --- |
| `SessionStart` | Recalls key facts about you and the project, and adds them to the agent's context. |
| `UserPromptSubmit` | Recalls memories relevant to the prompt, and adds them to the agent's context. |
| `Stop` | Stores the exchange — your prompt and the agent's reply — through `remember`, so Agent Memory extracts and reconciles what it says. |

Recalled memories are labelled as background, not instructions. Each hook makes one call to the
context's `/mcp` endpoint with an 8-second limit, and fails open: if memory is off, unreachable or
slow, the prompt goes ahead with nothing added. The hooks are
[`agent-memory-hook.sh`](bin/agent-memory-hook.sh), and use the same protocol as the hooks in
SurrealDB's own Claude Code plugin.

**What leaves the sandbox.** With automatic memory on, every prompt you send and every reply the
agent gives is sent to your context, over the same proxy and to the same host as everything
else. Anything you paste into a prompt is stored with it.

**Codex asks first.** Codex runs hooks from its user configuration only once you have trusted
them. Until then it skips them — the interactive session warns at startup; `codex exec` skips them
silently. Run `/hooks` and trust the three Agent Memory hooks once per sandbox; the kit writes
them identically on every boot, so the trust lasts until the sandbox is removed.

**Turning it off.** Create the sandbox with `--kit-arg hooks=off`, or `-e AGENT_MEMORY_HOOKS=off`.
The hooks are not registered, and the MCP server and CLI are still there for the agent to use on
demand.

## How it works

**The CLI** is a static binary, so it runs on any workload. The recipe downloads the release named
by `args.version` from `download.surrealdb.com`, verifies it against the published checksum, and
checks the version it reports. The network policy does not include `download.surrealdb.com`, so
`agent-memory upgrade` cannot replace it inside the sandbox: change the version here instead.

**The profile** at `~/.config/spectron/config.toml` holds the context URL and id. The API key comes
from `SPECTRON_API_KEY`, which holds the placeholder.

**The MCP server** is the context's own `https://<host>/mcp`. A startup hook registers it on every
boot — with `claude mcp add --scope user` and `codex mcp add` when those CLIs are present — so it
survives the workload rewriting its configuration. The hook never fails the boot.

**The hooks** are registered by the same startup hook, merged into `~/.claude/settings.json` and
`~/.codex/hooks.json`. Hooks you have configured yourself are left alone, and a file that is not
valid JSON is not touched.

**The instructions** reach the agent through its profile (`CLAUDE.md`, `AGENTS.md`), which lists
the kit and points at `/usr/share/sandbox/kit/agent-memory/agent-memory-context.md`.

## Configuration

| Argument | Required | What it does |
| --- | --- | --- |
| `host` | yes | Your context host, without `https://`. It is the only host the sandbox may reach, and the only one that receives the key. |
| `contextId` | yes | Your context id, exported as `SPECTRON_CONTEXT_ID` for the CLI. |
| `hooks` | no | `on` (default) or `off`: [automatic memory](#automatic-memory) in Claude Code and Codex. Exported as `AGENT_MEMORY_HOOKS`, so `-e AGENT_MEMORY_HOOKS=off` works too. |
| `version` | no | The `agent-memory` CLI release, `0.3.0` by default. A build argument: change the default here, or pass `--build-arg version=…` to buildx. |

A self-hosted Agent Memory server can be used the same way, provided it is served over HTTPS on
port 443 under a DNS name the sandbox can resolve: pass that name as `host`.

## Testing

[`scripts/smoke-agent-memory.sh`](../scripts/smoke-agent-memory.sh) composes the kit onto shell,
Claude Code and Codex workloads and checks each one. With no arguments it uses `httpbin.org` as a
stand-in context host, which echoes the request headers back and so proves the proxy presents
the stored key; bind the `agent-memory` secret for `httpbin.org` first, and set
`AGENT_MEMORY_EXPECT_KEY` to a throwaway value you stored there to assert it exactly.

In the Claude Code and Codex sandboxes it also runs
[`check-hooks.sh`](../scripts/agent-memory/check-hooks.sh) against a stand-in `/mcp` server inside
the sandbox: the hooks are registered, recall adds memories to the context, remember stores the
exchange, a dead endpoint fails open, and the agent itself fires the hooks. That last check needs
no agent login — the hooks fire before the model call does.

Against your own context it also stores a fact, recalls it through the CLI and through the recall
hook, and forgets it again:

```bash
AGENT_MEMORY_HOST=abc123.spectron.cloud AGENT_MEMORY_CONTEXT_ID=<your-context-id> \
  ./scripts/smoke-agent-memory.sh
```
