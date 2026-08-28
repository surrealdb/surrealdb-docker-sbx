#!/usr/bin/env python3
"""Assert the invariants of the SurrealDB sandbox kit.

These are the properties that would either silently break the kit or quietly
widen its security contract, so they are pinned here: changing one means
changing this file too, which makes it visible in review.
"""

import pathlib
import sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parents[2]

# The kit's complete outbound network contract, mirrored from SECURITY.md.
EXPECTED_DOMAINS = {"install.surrealdb.com", "download.surrealdb.com"}

errors = []


def check(condition, message):
    if not condition:
        errors.append(message)


spec = yaml.safe_load((ROOT / "spec.yaml").read_text())

check(spec.get("schemaVersion") == "2", "schemaVersion must be the string '2'")
check(spec.get("kind") == "sandbox", "kind must be 'sandbox'")
check(spec.get("name") == "surrealdb", "name must be 'surrealdb'")
check(bool(spec.get("version")), "version must be set")

sandbox = spec.get("sandbox") or {}
check(bool(sandbox.get("image")), "sandbox.image must be set")
check(bool(sandbox.get("entrypoint")), "sandbox.entrypoint must be set")

allowed = set((spec.get("permissions") or {}).get("network", {}).get("allow") or [])
check(
    allowed == EXPECTED_DOMAINS,
    f"network allow-list changed: {sorted(allowed)} != {sorted(EXPECTED_DOMAINS)}. "
    "Update SECURITY.md and this check together.",
)

env = (spec.get("environment") or {}).get("variables") or {}
for required in ("SURREAL_BIND", "SURREAL_USER", "SURREAL_PASS", "SURREAL_STORAGE"):
    check(required in env, f"environment.variables.{required} must be set")

setup = spec.get("setup") or {}
install = setup.get("install") or []
startup = setup.get("startup") or []

check(
    any("install.surrealdb.com" in str(step.get("command", "")) for step in install),
    "setup.install must install SurrealDB from install.surrealdb.com",
)
check(
    any(step.get("background") for step in startup),
    "setup.startup must start SurrealDB as a background service",
)
check(
    len(startup) >= 2 and not startup[-1].get("background"),
    "setup.startup must end with a foreground readiness gate",
)

# Every helper script the spec invokes must actually ship in files/home/.
for step in install + startup:
    command = step.get("command")
    words = command.split() if isinstance(command, str) else list(command or [])
    for word in words:
        if word.startswith("/home/agent/") and word.endswith(".sh"):
            shipped = ROOT / "files" / "home" / word[len("/home/agent/") :]
            check(shipped.is_file(), f"spec references {word} but {shipped} is missing")

ports = {port.get("container") for port in (spec.get("ports") or [])}
check(8000 in ports, "port 8000 must be published")

if errors:
    print("spec.yaml validation failed:", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    sys.exit(1)

print("spec.yaml OK")
