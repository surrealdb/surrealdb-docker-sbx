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

This repository ships a [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/)
kit. Two properties of the kit are security-relevant and changes to them
warrant extra scrutiny in review:

- **The network allow-list** in `spec.yaml` under `permissions.network.allow`
  is the sandbox's *complete* outbound contract. Adding a domain widens what
  the sandbox can reach.
- **The install step** pipes `https://install.surrealdb.com` into a shell.
  Changing that URL, or the commands under `setup.install`, changes what code
  runs as root at sandbox creation.

The sandbox deliberately starts SurrealDB with the well-known root credentials
`root`/`root`, reachable only from inside the microVM and from `127.0.0.1` on
the host. It is a disposable development environment and must not be used to
hold production or sensitive data.
