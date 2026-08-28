# SurrealDB for Docker Sandboxes

A [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) **kit** that gives you a disposable
microVM with SurrealDB already running and the SurrealDB CLI on `PATH`.

No local install, no `docker run` incantation, no port juggling. One command and you are at a
prompt in front of a live database that you can throw away when you are done.

```bash
sbx run shell --kit github.com/surrealdb-dev/surrealdb-docker-sbx
```

```
surrealdb: starting on 0.0.0.0:8000 (path: memory)
surrealdb: ready at http://127.0.0.1:8000
agent@sandbox:~$ surreal sql --ns demo --db demo
```

## Why a sandbox

Docker Sandboxes run each environment in its own microVM with its own filesystem, network, and
Docker daemon. For a database that means you can wipe it, fill it with junk, or hand it to a
coding agent without any of that reaching your machine. Outbound network access is denied by
default — this kit opens exactly two domains, and nothing else.

## Requirements

- [`sbx`](https://docs.docker.com/ai/sandboxes/install/) — on macOS: `brew trust docker/tap && brew install docker/tap/sbx`
- A Docker login: `sbx login`

## Usage

Run straight from this repository:

```bash
sbx run shell --kit github.com/surrealdb-dev/surrealdb-docker-sbx
```

Or from a local clone, which is what you want if you are changing the kit:

```bash
git clone https://github.com/surrealdb-dev/surrealdb-docker-sbx
sbx run shell --kit ./surrealdb-docker-sbx
```

Mount a project directory into the sandbox by passing it as a positional argument:

```bash
sbx run shell --kit ./surrealdb-docker-sbx ~/my-project
```

### Talking to the database

`SURREAL_USER` and `SURREAL_PASS` are set in the sandbox environment, and the CLI reads both, so
no credential flags are needed:

```bash
surreal sql --ns demo --db demo             # interactive REPL
surreal is-ready --endpoint "$SURREAL_ENDPOINT"
surreal import --ns demo --db demo examples/seed.surql
```

The server listens on port 8000 inside the sandbox. To reach it from the host — with your own
application, or a GUI such as Surrealist — publish the port:

```bash
sbx run shell --kit . -p 8000:8000
```

`sbx ports` lists what is currently published.

## Configuration

Everything is an environment variable, set with `sbx run -e KEY=VALUE`.

| Variable | Default | What it does |
| --- | --- | --- |
| `SURREAL_STORAGE` | `memory` | `memory` or `rocksdb`. See [Storage](#storage). |
| `SURREAL_DATA_DIR` | `~/.surrealdb/data` | Where `rocksdb` keeps its files. |
| `SURREAL_PATH` | *(unset)* | Escape hatch: any path the CLI understands, e.g. `surrealkv://…`. Overrides `SURREAL_STORAGE`. |
| `SURREAL_BIND` | `0.0.0.0:8000` | Listen address inside the sandbox. |
| `SURREAL_USER` / `SURREAL_PASS` | `root` / `root` | Root credentials, seeded at first start. |
| `SURREAL_ENDPOINT` | `http://127.0.0.1:8000` | Used by the readiness gate; handy for your own scripts. |

### Storage

The default is **in-memory**: fastest to start, and it matches the disposable nature of a
sandbox. Everything is gone when the sandbox stops.

For data that survives a restart, switch to RocksDB:

```bash
sbx run shell --kit . -e SURREAL_STORAGE=rocksdb
```

That writes to `~/.surrealdb/data` inside the sandbox, which the kit declares as a volume, so it
persists across restarts of the same sandbox. It does *not* survive `sbx rm`.

## What the kit does

On creation it installs SurrealDB from `install.surrealdb.com`. On every start it runs
[`surrealdb-start.sh`](files/home/.local/bin/surrealdb-start.sh) in the background, then blocks on
[`surrealdb-wait.sh`](files/home/.local/bin/surrealdb-wait.sh) until the server accepts
connections — so your shell never opens in front of a database that is not up yet.

Its complete outbound network contract is two domains:

- `install.surrealdb.com` — the install script
- `download.surrealdb.com` — the binaries it fetches

Everything else is denied by the sandbox.

## Security

This is a development environment. It starts SurrealDB with the well-known root credentials
`root`/`root`, reachable only from inside the microVM and from `127.0.0.1` on the host. Do not put
production or sensitive data in it. See [SECURITY.md](SECURITY.md).

## Development

```bash
sbx kit validate .        # check the spec parses and is well-formed
sbx kit inspect .         # show what the kit resolves to
./scripts/smoke.sh        # boot a sandbox and round-trip a query
```

CI runs `shellcheck` over the sandbox scripts and asserts the spec's invariants — including that
the network allow-list has not silently grown.

## License

[Apache 2.0](LICENSE)
