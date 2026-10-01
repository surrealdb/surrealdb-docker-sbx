#!/usr/bin/env python3
"""Assert the invariants of the sandbox kits in this repository.

These are the properties that would either silently break the kits or quietly
widen their security contract, so they are pinned here: changing one means
changing this file too, which makes it visible in review.
"""

import pathlib
import re
import sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parents[2]

# Each kit lives in a directory named for its stem: <stem>/<stem>.yaml and
# <stem>/<stem>.dockerfile. The two surrealdb kits ship the same server and
# must move together; agent-memory stands alone.
SURREALDB_KITS = {"surrealdb": "workload", "surrealdb-mixin": "mixin"}

# The only host any recipe may fetch from at build time, mirrored from
# SECURITY.md.
EXPECTED_DOWNLOAD_HOSTS = {"download.surrealdb.com"}

REQUIRED_SURREAL_ENV = {"SURREAL_BIND", "SURREAL_USER", "SURREAL_PASS", "SURREAL_ENDPOINT", "SURREAL_STORAGE"}
VERSION_REF = "${{ kit.args.version }}"
HOST_REF = "${{ kit.args.host }}"
CAP = "com.docker.sandbox/"

errors = []


def check(condition, message):
    if not condition:
        errors.append(message)


def recipe_env(text):
    """The ENV KEY="value" assignments a recipe makes, one per line."""
    return dict(re.findall(r'^ENV (\w+)="([^"]*)"$', text, re.MULTILINE))


def recipe_hosts(text):
    """Hosts the recipe fetches from, ignoring comments and ENV values."""
    lines = [line for line in text.splitlines() if not line.lstrip().startswith(("#", "ENV "))]
    return set(re.findall(r"https?://([^/\"'\s]+)", "\n".join(lines)))


def check_kit(stem, kind, provides, build_arg, env_prefix):
    """The checks every kit shares. Returns its descriptor, capabilities by
    type, and recipe text."""
    kit_dir = ROOT / stem
    where = f"{stem}.yaml"
    raw = (kit_dir / where).read_text()
    check(
        raw.startswith("# syntax=docker/sandbox-kit:3\n"),
        f"{where}: first line must be '# syntax=docker/sandbox-kit:3'",
    )
    spec = yaml.safe_load(raw)

    check(spec.get("schemaVersion") == "3", f"{where}: schemaVersion must be the string '3'")
    check(spec.get("kind") == kind, f"{where}: kind must be '{kind}'")
    check("name" not in spec, f"{where}: v3 has no top-level name; identity is the reference")
    for field in ("sourceUrl", "licenses"):
        check(bool(spec.get(field)), f"{where}: {field} must be set")
    check(spec.get("version") == VERSION_REF, f"{where}: version must be {VERSION_REF}")
    check(
        spec.get("provides") == [f"{provides}@{VERSION_REF}"],
        f"{where}: provides must be exactly {provides}@{VERSION_REF}",
    )
    version_arg = (spec.get("args") or {}).get("version") or {}
    check(version_arg.get("buildArg") == build_arg, f"{where}: args.version must feed {build_arg}")

    caps = {}
    for entry in spec.get("capabilities") or []:
        caps.setdefault(entry.get("type", ""), []).append(entry)
    check((CAP + "sbx@1" in caps) == (kind == "workload"), f"{where}: sbx@1 belongs on a workload only")

    lifecycle = ((caps.get(CAP + "lifecycle@1") or [{}])[0]).get("config") or {}
    check("install" not in lifecycle, f"{where}: content is installed by the recipe, not an install hook")
    check(("interactive" in lifecycle) == (kind == "workload"), f"{where}: interactive belongs on a workload only")

    # Hook environments are deny-by-default: every variable in the kit's
    # namespace that a hook's script reads must be declared in that hook's
    # env, or it never arrives.
    for step in lifecycle.get("startup") or []:
        command = step.get("command")
        words = command.split() if isinstance(command, str) else list(command or [])
        for word in words:
            if word.startswith("/usr/local/bin/") and word.endswith(".sh"):
                script = kit_dir / "bin" / word[len("/usr/local/bin/") :]
                if not script.is_file():
                    check(False, f"{where}: startup runs {word} but {script} is missing")
                    continue
                read = set(re.findall(rf"\b(?:{env_prefix})\w+", script.read_text()))
                missing = read - set(step.get("env") or [])
                check(not missing, f"{where}: hook {word} reads {sorted(missing)} but does not declare them in env")

    context = (caps.get(CAP + "agent-context@1") or [{}])[0].get("config") or {}
    if kind == "mixin" and context:
        check("filename" not in context, f"{where}: a mixin's agent-context cannot own a filename")
        content_file = context.get("contentFile", "")
        check(
            bool(content_file) and (kit_dir / content_file).is_file(),
            f"{where}: agent-context contentFile {content_file!r} must exist",
        )

    recipe = (kit_dir / f"{stem}.dockerfile").read_text()
    hosts = recipe_hosts(recipe)
    check(
        hosts == EXPECTED_DOWNLOAD_HOSTS,
        f"{stem}.dockerfile: downloads changed: {sorted(hosts)} != {sorted(EXPECTED_DOWNLOAD_HOSTS)}. "
        "Update SECURITY.md and this check together.",
    )
    check("COPY --chmod=0755 bin/" in recipe, f"{stem}.dockerfile: must ship bin/ executable")
    return spec, caps, recipe


# --- surrealdb and surrealdb-mixin --------------------------------------------

defaults = {}
envs = {}
scripts = {}

for stem, kind in SURREALDB_KITS.items():
    where = f"{stem}.yaml"
    spec, caps, recipe = check_kit(stem, kind, "surrealdb", "SURREAL_VERSION", "SURREAL_")
    defaults[stem] = ((spec.get("args") or {}).get("version") or {}).get("default")

    check(
        not any(t.startswith(CAP + "network-policy@") for t in caps),
        f"{where}: the surrealdb kits request no network access; adding a network-policy "
        "widens the contract. Update SECURITY.md and this check together.",
    )
    check(CAP + "long-running@1" in caps, f"{where}: long-running@1 must be declared")

    ports = {(e.get("config") or {}).get("container") for e in caps.get(CAP + "port@1", [])}
    check(8000 in ports, f"{where}: port 8000 must be published")

    volumes = {(e.get("config") or {}).get("path"): (e.get("config") or {}) for e in caps.get(CAP + "volume@1", [])}
    volume = volumes.get("/home/agent/.surrealdb")
    check(volume is not None and bool(volume.get("size")), f"{where}: /home/agent/.surrealdb must be a sized volume")

    startup = (((caps.get(CAP + "lifecycle@1") or [{}])[0]).get("config") or {}).get("startup") or []
    check(
        any(step.get("background") for step in startup),
        f"{where}: lifecycle startup must start SurrealDB as a background service",
    )
    check(
        len(startup) >= 2 and not startup[-1].get("background"),
        f"{where}: lifecycle startup must end with a foreground readiness gate",
    )

    envs[stem] = recipe_env(recipe)
    missing_env = REQUIRED_SURREAL_ENV - set(envs[stem])
    check(not missing_env, f"{stem}.dockerfile: must set ENV {sorted(missing_env)}")
    scripts[stem] = {p.name: p.read_bytes() for p in sorted((ROOT / stem / "bin").glob("*.sh"))}

check(len(set(defaults.values())) == 1, f"the surrealdb kits must install the same release: {defaults}")
check(envs["surrealdb"] == envs["surrealdb-mixin"], "the surrealdb kits' recipes must set the same ENV")
check(
    scripts["surrealdb"] == scripts["surrealdb-mixin"],
    "surrealdb/bin and surrealdb-mixin/bin must hold byte-identical scripts",
)

# --- agent-memory ---------------------------------------------------------------

where = "agent-memory.yaml"
spec, caps, recipe = check_kit(
    "agent-memory", "mixin", "agent-memory", "AGENT_MEMORY_VERSION", "SPECTRON_|AGENT_MEMORY_"
)
args = spec.get("args") or {}

check((args.get("host") or {}).get("required") is True, f"{where}: args.host must be required")
check("env" not in (args.get("host") or {}), f"{where}: args.host is policy input, not environment")
check(
    (args.get("contextId") or {}).get("env") == "SPECTRON_CONTEXT_ID",
    f"{where}: args.contextId must export SPECTRON_CONTEXT_ID",
)
hooks_arg = args.get("hooks") or {}
check(
    hooks_arg.get("enum") == ["on", "off"] and hooks_arg.get("env") == "AGENT_MEMORY_HOOKS",
    f"{where}: args.hooks must be on|off and export AGENT_MEMORY_HOOKS",
)
check(
    (ROOT / "agent-memory" / "bin" / "agent-memory-hook.sh").is_file(),
    "agent-memory/bin/agent-memory-hook.sh must ship: the setup script registers it",
)

# The complete outbound contract: the caller's context host, at runtime only.
policies = caps.get(CAP + "network-policy@1") or []
check(
    not any(t.startswith(CAP + "network-policy@2") for t in caps) and len(policies) == 1,
    f"{where}: exactly one network-policy@1 must be declared",
)
policy = (policies[0].get("config") or {}) if policies else {}
check(
    set(policy) == {"runtime"} and policy["runtime"] == {"allow": [HOST_REF]},
    f"{where}: the network policy must allow the context host at runtime and nothing else. "
    "Update SECURITY.md and this check together.",
)

# The API key: proxy-managed, so the sandbox holds a placeholder, and
# presented to the context host only.
credentials = caps.get(CAP + "credential@1") or []
check(len(credentials) == 1, f"{where}: exactly one credential must be declared")
credential = (credentials[0].get("config") or {}) if credentials else {}
api_key = credential.get("apiKey") or {}
check(
    credential.get("service") == "agent-memory" and credential.get("phase") == "runtime",
    f"{where}: the credential must be service agent-memory, phase runtime",
)
check(
    api_key.get("proxyManaged") is True and api_key.get("name") == "SPECTRON_API_KEY",
    f"{where}: the API key must be proxy-managed in SPECTRON_API_KEY",
)
check(
    [rule.get("domain") for rule in api_key.get("inject") or []] == [HOST_REF],
    f"{where}: the API key must be presented to the context host and nothing else",
)

check("sha256sum -c" in recipe, "agent-memory.dockerfile: the CLI download must be checksum-verified")

if errors:
    print("kit validation failed:", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    sys.exit(1)

print("kits OK")
