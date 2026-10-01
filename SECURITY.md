# Security Policy

## Reporting a Vulnerability

We take the security of SurrealDB code, software, and cloud platform very
seriously. If you believe you have found a security vulnerability in
SurrealDB, we encourage you to let us know right away. We will investigate
all legitimate reports and do our best to quickly fix the problem.

Please report any issues or vulnerabilities to security@surrealdb.com,
instead of posting a public issue in GitHub. Please include the version
identifier, by running `surreal version` on the command-line, and
details on how the vulnerability can be exploited.

## Scope notes for this repository

This repository ships three [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/)
kits, `surrealdb`, `surrealdb-mixin` and `agent-memory`, each a v3 descriptor
(`<kit>/<kit>.yaml`) and the recipe that builds its content
(`<kit>/<kit>.dockerfile`). These properties of the kits are security-relevant
and changes to them warrant extra scrutiny in review:

- **The network contract.** Neither SurrealDB descriptor declares a
  `com.docker.sandbox/network-policy` capability: those sandboxes request no
  outbound access at all. `agent-memory` allows exactly one host, at runtime:
  the context host the user supplies as `args.host`. Adding a policy, an
  allow entry, or an install-phase grant widens what the sandbox can reach.
- **The API key.** `agent-memory` declares one `credential@1`, service
  `agent-memory`, proxy-managed: the sandbox holds a placeholder in
  `SPECTRON_API_KEY`, and the proxy presents the real key only on requests
  to the context host. Making it not proxy-managed, or adding an inject
  domain, exposes the key or sends it somewhere new.
- **What `agent-memory` sends.** Unless created with `hooks=off`, its hooks
  send every prompt and agent reply in Claude Code and Codex to the context
  host, and inject recalled memories into the agent's context. They run
  `agent-memory/bin/agent-memory-hook.sh`, registered in the agents' user
  configuration; Codex's own trust review of those hooks is left in place.
- **The install step.** Each recipe downloads a pinned release from
  `https://download.surrealdb.com` at build time and verifies it — by version,
  and for the `agent-memory` CLI also by its published checksum. Changing
  that URL, the recipes, or `args.version` changes the binary that ships in
  the kit. The startup hooks run the scripts in each kit's `bin/` directory
  on every boot; the SurrealDB kits also re-own their volume as root.

The sandbox deliberately starts SurrealDB with the well-known root credentials
`root`/`root`, reachable only from inside the microVM and from `127.0.0.1` on
the host. It is a disposable development environment and must not be used to
hold production or sensitive data.
