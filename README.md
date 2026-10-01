# SurrealDB for Docker Sandboxes

[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) **kits** that give you a disposable
microVM with SurrealDB already running and the SurrealDB CLI on `PATH`.

No local install, no `docker run` incantation, no port juggling. One command and you are at a
prompt in front of a live database that you can throw away when you are done.

```bash
sbx run 'git+https://github.com/surrealdb-dev/surrealdb-docker-sbx.git#dir=surrealdb'
```

```
$ surreal sql --ns demo --db demo
```

This repository ships three [v3 kits](https://github.com/docker/sandbox-kit-spec):

| Kit | Kind | Use it for |
| --- | --- | --- |
| [`surrealdb`](surrealdb/) | workload | A shell sandbox with SurrealDB running in it. |
| [`surrealdb-mixin`](surrealdb-mixin/) | mixin | Adding SurrealDB to a coding agent's sandbox — Claude Code, Codex, and so on — and telling the agent it is there. |
| [`agent-memory`](agent-memory/) | mixin | Giving a coding agent persistent memory that outlives the sandbox, backed by [SurrealDB Agent Memory](https://surrealdb.com/docs/agent-memory) — recalled and stored automatically in Claude Code and Codex. See its [README](agent-memory/README.md). |

## Why a sandbox

Docker Sandboxes run each environment in its own microVM with its own filesystem, network, and
Docker daemon. For a database that means you can wipe it, fill it with junk, or hand it to a
coding agent without any of that reaching your machine. Outbound network access is denied by
default — the SurrealDB kits request none at all, and `agent-memory` only your own context host.

## Requirements

- [`sbx`](https://docs.docker.com/ai/sandboxes/install/) 0.46 or later — on macOS:
  `brew trust docker/tap && brew install docker/tap/sbx`
- A Docker login: `sbx login`

## Usage

### A SurrealDB sandbox

Run the `surrealdb` kit straight from this repository:

```bash
sbx run 'git+https://github.com/surrealdb-dev/surrealdb-docker-sbx.git#dir=surrealdb'
```

Quote the reference — `#` and `&` mean something to your shell. Pin a commit or tag with
`#ref=<ref>&dir=surrealdb`.

Or from a local clone, which is what you want if you are changing the kits:

```bash
git clone https://github.com/surrealdb-dev/surrealdb-docker-sbx
cd surrealdb-docker-sbx
sbx run ./surrealdb
```

The current directory is mounted as the workspace. Mount a different project by passing it after
the kit:

```bash
sbx run ./surrealdb ~/my-project
```

### SurrealDB for a coding agent

Compose the `surrealdb-mixin` kit onto an agent's workload kit with `--kit`. The agent gets the
same running server and CLI, plus a note in its instructions saying where the database is and
how to use it:

```bash
sbx run docker/sbx-kit-claude:2.1.278 \
  --kit 'git+https://github.com/surrealdb-dev/surrealdb-docker-sbx.git#dir=surrealdb-mixin'
```

v3 mixins compose onto v3 workloads only — the `docker` organisation's `sbx-kit-*` kits on
[Docker Hub](https://hub.docker.com/search?type=sbx_kit&badges=verified_publisher), such as
`docker/sbx-kit-codex` or `docker/sbx-kit-shell`. The built-in agent names (`sbx run claude`,
`sbx run shell`) are still v2 and cannot take it. Do not compose the mixin with the `surrealdb`
workload: both provide SurrealDB, and `sbx` refuses the pair.

### Memory for a coding agent

The `agent-memory` kit connects the agent to your SurrealDB Agent Memory context, so what it
learns in one sandbox it can recall in the next. In Claude Code and Codex it works automatically:
relevant memories are recalled into the agent's context with every prompt, and every finished
exchange is stored. Store the context's API key on your host once, then compose the kit with your
context's host and id:

```bash
sbx secret set agent-memory
sbx run docker/sbx-kit-claude:2.1.278 \
  --kit 'git+https://github.com/surrealdb-dev/surrealdb-docker-sbx.git#dir=agent-memory' \
  --kit-arg host=abc123.spectron.cloud \
  --kit-arg contextId=<your-context-id>
```

The key stays on your host. [agent-memory/README.md](agent-memory/README.md) covers approving it,
trusting the hooks in Codex, turning automatic memory off, unattended runs, and using it alongside
the `surrealdb-mixin`.

### Talking to the database

`SURREAL_USER` and `SURREAL_PASS` are set in the sandbox environment, and the CLI reads both, so
no credential flags are needed:

```bash
surreal sql --ns demo --db demo                         # interactive REPL
surreal is-ready --endpoint "$SURREAL_ENDPOINT"
surreal sql --ns demo --db demo < examples/seed.surql   # run a script (this repo as workspace)
```

Load hand-written `.surql` files through `surreal sql`. Since SurrealDB 3.0, `surreal import` is
for restoring `surreal export` dumps: it requires `OPTION IMPORT;` as the first statement and
skips `DEFAULT`, `VALUE` and `ASSERT` clauses.

### Reaching it from the host

The server listens on port 8000 inside the sandbox, and the kits publish it: `sbx ls` shows the
host port, which is allocated afresh each time the sandbox starts. For your own application, or a
GUI such as Surrealist, pin it and run the sandbox detached so it keeps serving with no session
attached:

```bash
sbx run -d --name surrealdb -p 8000:8000 ./surrealdb
# connect to http://127.0.0.1:8000 as root/root
sbx stop surrealdb
```

The kits declare [`long-running@1`](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/capabilities/com.docker.sandbox/long-running%401.md),
asking the runtime to keep a database running after its last session closes. `sbx` 0.46 does not
honour it yet — an interactive sandbox still stops shortly after you exit — so use `-d` for a
server you want to stay up.

## Configuration

Everything is an environment variable, set with `sbx run -e KEY=VALUE` when the sandbox is
created.

| Variable | Default | What it does |
| --- | --- | --- |
| `SURREAL_STORAGE` | `memory` | `memory` or `rocksdb`. See [Storage](#storage). |
| `SURREAL_DATA_DIR` | `~/.surrealdb/data` | Where `rocksdb` keeps its files. |
| `SURREAL_PATH` | *(unset)* | Escape hatch: any path the CLI understands, e.g. `surrealkv://…`. Overrides `SURREAL_STORAGE`. |
| `SURREAL_BIND` | `0.0.0.0:8000` | Listen address inside the sandbox. |
| `SURREAL_USER` / `SURREAL_PASS` | `root` / `root` | Root credentials, seeded at first start. |
| `SURREAL_ENDPOINT` | `http://127.0.0.1:8000` | Used by the readiness gate; handy for your own scripts. |
| `SURREAL_WAIT_ATTEMPTS` | `60` | How many half-second polls the readiness gate makes before giving up. |

These are the variables the kits' startup hooks declare, and under the v3 kit specification a
hook receives only what it declares. To pass the server any other `SURREAL_*` setting, add it to
the start hook's `env` list in both kit descriptors.

### Storage

The default is **in-memory**: fastest to start, and it matches the disposable nature of a
sandbox. Everything is gone when the sandbox stops.

For data that survives a restart, switch to RocksDB:

```bash
sbx run -e SURREAL_STORAGE=rocksdb ./surrealdb
```

That writes to `~/.surrealdb/data` inside the sandbox, which the kits declare as a volume, so it
persists across restarts of the same sandbox. It does *not* survive `sbx rm`.

### SurrealDB version

The kits install SurrealDB 3.3.0. To ship another release, change `args.version.default` in both
descriptors — CI fails if they differ. Building with buildx directly, pass it as a build argument
instead: `--build-arg version=3.2.4`.

## What the kits do

When a kit is built, its recipe downloads the pinned SurrealDB release from
`download.surrealdb.com` and checks that `surreal version` reports it. Nothing is installed when
a sandbox is created.

On every start the kit hands its volume to the `agent` user, runs
[`surrealdb-start.sh`](surrealdb/bin/surrealdb-start.sh) in the background, then blocks on
[`surrealdb-wait.sh`](surrealdb/bin/surrealdb-wait.sh) until the server accepts connections — so
your shell never opens in front of a database that is not up yet. The server's output goes to
`/var/log/sbx-kit-startup.log`, and each kit's own descriptor and recipe are readable in place
under `/usr/share/sandbox/kit/`.

Neither SurrealDB kit requests any outbound network access, so the sandbox can reach nothing
beyond what your own `sbx` policy allows.

## Security

This is a development environment. It starts SurrealDB with the well-known root credentials
`root`/`root`, reachable only from inside the microVM and from `127.0.0.1` on the host. Do not put
production or sensitive data in it. See [SECURITY.md](SECURITY.md).

## Development

Each kit is a directory holding a v3 descriptor and the Dockerfile recipe that builds its
content:

```
surrealdb/            surrealdb.yaml, surrealdb.dockerfile, bin/
surrealdb-mixin/      surrealdb-mixin.yaml, surrealdb-mixin.dockerfile, surrealdb-context.md, bin/
agent-memory/         agent-memory.yaml, agent-memory.dockerfile, agent-memory-context.md, bin/
```

The `surrealdb` and `surrealdb-mixin` `bin/` directories hold the same scripts — a kit can only
read its own directory when it builds — and CI fails if they drift apart.

```bash
# Validate and build a kit: the kit frontend checks the descriptor first, in a second.
docker buildx build surrealdb -f surrealdb/surrealdb.yaml --output type=cacheonly

# Show what a kit resolves to, as sbx sees it.
sbx kit inspect ./surrealdb

# Boot the SurrealDB kits in real sandboxes and round-trip a query in each.
./scripts/smoke.sh
SURREAL_STORAGE=rocksdb ./scripts/smoke.sh

# Compose agent-memory onto shell, Claude Code and Codex (see agent-memory/README.md).
./scripts/smoke-agent-memory.sh
```

`sbx` builds kits from source with your default buildx builder, which has to be able to export
OCI images. If it reports that the OCI exporter is not supported for the `docker` driver, create
a `docker-container` builder and point `sbx` at it:

```bash
docker buildx create --name kits --driver docker-container
export BUILDX_BUILDER=kits
```

To check a kit against the specification's conformance suite, export it as an OCI layout and run
[`kit-tck`](https://github.com/docker/sandbox-kit-spec/releases):

```bash
docker buildx build surrealdb -f surrealdb/surrealdb.yaml -t surrealdb:dev \
  --output type=oci,dest=/tmp/surrealdb-layout,tar=false
kit-tck validate --layout /tmp/surrealdb-layout dev
```

CI runs `shellcheck` over the scripts and asserts the kits' invariants — including that the
SurrealDB kits have not started asking for network access, and that `agent-memory` reaches only
the context host and keeps its key proxy-managed. It then builds every kit, runs `kit-tck`
against them, audits the mixins' file ownership, and smoke-tests the SurrealDB workload image.

## Contributing

Contributions are welcome. Please read our [Code of Conduct](CODE_OF_CONDUCT.md) first, and
report security issues privately per [SECURITY.md](SECURITY.md) rather than opening an issue.

## License

The kits are [Apache 2.0](LICENSE), as is the `agent-memory` CLI. The SurrealDB server the
SurrealDB kits install is distributed under the
[Business Source License 1.1](https://github.com/surrealdb/surrealdb/blob/main/LICENSE).
