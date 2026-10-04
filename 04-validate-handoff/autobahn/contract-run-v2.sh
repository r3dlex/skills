#!/usr/bin/env bash
#
# contract-run-v2.sh - the pinned readiness-contract/2 entry point.
#
# Reached only through the route prelude of contract-run.sh, which dispatches v2
# operation names here and leaves every v1 name on the unchanged v1 path. Before
# anything runs, the bytes about to run are checked against
# readiness-dependency-v2.json (autobahn and northstar copies must be identical).
#
# The driver starts in an allowlisted environment: PATH, LANG, LC_ALL, TMPDIR,
# SSH_AUTH_SOCK and GH_TOKEN (when present) pass through; HOME and GH_CONFIG_DIR
# are set from the passwd home directory, never inherited, so keyring-authenticated
# gh keeps working; everything else (GH_HOST, GH_REPO, GIT_*, SKIP_*, waivers) is
# dropped. Unknown arguments exit 2. No text, flag or variable maps to a waiver.
# The git repository selection variables (GIT_DIR, GIT_COMMON_DIR, GIT_WORK_TREE,
# GIT_INDEX_FILE, GIT_OBJECT_DIRECTORY) pass through only so the observer refuses an
# identity observation they would redirect (identity_git_env_injected); no command
# the observer starts ever receives them.
#
# No heredoc, here-string or temporary file is used here, so merge-authority.sh
# still reaches a decision without a writable TMPDIR.
#
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASSWD_HOME="$(python3 -I -B -c 'import os, pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')"
ALLOWED=("PATH=${PATH:-/usr/bin:/bin}" "HOME=$PASSWD_HOME" "GH_CONFIG_DIR=$PASSWD_HOME/.config/gh")
for name in LANG LC_ALL TMPDIR SSH_AUTH_SOCK GH_TOKEN GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY; do
  if [[ -n "${!name+set}" ]]; then
    ALLOWED+=("$name=${!name}")
  fi
done
DRIVER='
import argparse, hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
expected = {"lib/readiness_contract_v2.py", "lib/observer.py", "lib/readiness_contract.py", "lib/verification.py",
            "schemas/readiness-contract-v2.json", "contract-run.sh", "contract-run-v2.sh", "run-gates.sh",
            "merge-authority.sh", "prereq-check.sh", "migrate-handoff.sh", "northstar/handoff-write.sh",
            "tdd-evidence.sh", "tdd-mode.sh", "lint-gate.sh", "ci-gate.sh", "local-ci.sh", "lib/local_ci_contract.py",
            "northstar/approve.sh"}
def fail(message):
    print(json.dumps({"schema": "readiness-contract/2", "error": "dependency_failed:" + message,
                      "refusals": [{"code": "dependency_failed", "detail": message}]}))
    sys.exit(1)
try:
    manifest = json.loads((root / "readiness-dependency-v2.json").read_text())
    peer = root.parent / "northstar"
    if not peer.is_dir():
        peer = root.parent.parent / "02-govern-plan/northstar"
    if json.loads((peer / "readiness-dependency-v2.json").read_text()) != manifest:
        fail("producer/consumer fingerprint mismatch")
    if manifest.get("schema") != "readiness-contract/2" or set(manifest.get("files", {})) != expected:
        fail("unsupported or incomplete v2 dependency manifest")
    for name, digest in sorted(manifest["files"].items()):
        path = peer / name[len("northstar/"):] if name.startswith("northstar/") else root / name
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            fail("helper fingerprint mismatch: " + name)
except (OSError, ValueError, KeyError, AttributeError) as error:
    fail(str(error))
sys.path.insert(0, str(root / "lib"))
import observer
import readiness_contract_v2 as v2

def migrate(argv):
    """migrate-v2 (R1, O10): I/O glue only. Every decision lives in the pure v2.migrate_main;
    the candidate is printed, never written, and carries no authority. No driver-log entry is
    written: a no-authority transform leaves no observer state."""
    parser = argparse.ArgumentParser(prog="contract-run-v2.sh migrate-v2 (readiness-contract/2)",
                                     add_help=False, allow_abbrev=False)
    parser.add_argument("--to", required=True, choices=[v2.VERSION])
    parser.add_argument("--legacy", required=True)
    parser.add_argument("--inventory", required=True)
    parser.add_argument("--root", default=".")
    parser.add_argument("--target", default="main")
    try:
        args = parser.parse_args(argv)
    except SystemExit:
        result = {"schema": v2.VERSION, "refusals": [{"code": "usage", "detail": "unknown or missing argument"}]}
        print(json.dumps(result, indent=2, sort_keys=True))
        return 2
    try:
        selected = observer.observed_root(args.root)
        origin = observer.checked_provenance(selected, args.target)
        ref = observer.target_ref(args.target)
        legacy_data = pathlib.Path(args.legacy).read_bytes()
        legacy = observer.parse_json(legacy_data, "legacy")
        registry_bytes = observer.show(selected, ref, v2.V1_REGISTRY)
        registry = observer.parse_json(registry_bytes, "v1_registry") if registry_bytes is not None else None
        inventory = observer.parse_json(pathlib.Path(args.inventory).read_bytes(), "inventory")
        spec_path = legacy.get("spec", {}).get("path") if isinstance(legacy, dict) else None
        spec_bytes = observer.show(selected, ref, spec_path) if isinstance(spec_path, str) else None
        spec_sha256 = v2.sha256(spec_bytes) if spec_bytes is not None else None
        result = v2.migrate_main(legacy, v2.sha256(legacy_data), registry, inventory, spec_sha256)
        result["provenance"] = origin
        result["target_revision"] = observer.git_text(selected, "rev-parse", "--verify", ref + "^{commit}")
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    except v2.Invalid as error:
        detail = str(error).split(":", 1)[1] if ":" in str(error) else str(error)
        result = {"schema": v2.VERSION, "authority": v2.NO_AUTHORITY,
                  "refusals": [{"code": v2.code(error), "detail": detail}]}
        print(json.dumps(result, indent=2, sort_keys=True))
        return 1
    except (OSError, ValueError, KeyError, TypeError) as error:
        result = {"schema": v2.VERSION, "authority": v2.NO_AUTHORITY,
                  "refusals": [{"code": "operation_failed", "detail": "%s: %s" % (type(error).__name__, error)}]}
        print(json.dumps(result, indent=2, sort_keys=True))
        return 1

if sys.argv[2:3] == ["migrate-v2"]:
    sys.exit(migrate(sys.argv[3:]))
sys.exit(observer.main(sys.argv[2:]))
'
exec env -i "${ALLOWED[@]}" python3 -I -B -c "$DRIVER" "$HERE" "$@"