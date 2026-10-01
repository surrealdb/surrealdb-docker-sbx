# SurrealDB

A SurrealDB server is running in this sandbox, started at boot, with the
`surreal` CLI on `PATH`.

- **Endpoint:** `$SURREAL_ENDPOINT` (`http://127.0.0.1:8000`), HTTP and
  WebSocket (`ws://127.0.0.1:8000/rpc`) on port 8000.
- **Credentials:** root user `$SURREAL_USER` / `$SURREAL_PASS` (`root` /
  `root`). The CLI reads both from the environment, so commands need no
  credential flags. Connect from code with the same values.
- **Storage:** `$SURREAL_STORAGE` — `memory` by default, so data is lost
  when the sandbox stops; `rocksdb` persists it under `~/.surrealdb/data`.

Useful commands:

```sh
surreal is-ready --endpoint "$SURREAL_ENDPOINT"     # is the server up?
surreal sql --ns demo --db demo                     # interactive REPL
surreal sql --ns demo --db demo --json <<< 'SELECT * FROM person;'
surreal sql --ns demo --db demo < schema.surql      # run a .surql script
surreal export --ns demo --db demo dump.surql       # dump a database
surreal import --ns demo --db demo dump.surql       # restore a dump
```

`surreal import` only accepts files whose first statement is `OPTION IMPORT;`
(as `surreal export` writes them) and skips field processing — `DEFAULT`, `VALUE` and
`ASSERT` clauses do not run. Load hand-written scripts with `surreal sql`.

If the server is not answering, start it again with
`/usr/local/bin/surrealdb-start.sh &` and wait for it with
`/usr/local/bin/surrealdb-wait.sh`.

Write SurrealQL for the installed release (`surreal version`); it is a
development database with well-known credentials, so keep sensitive data out
of it.
