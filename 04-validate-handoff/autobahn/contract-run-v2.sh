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
#
# No heredoc, here-string or temporary file is used here, so merge-authority.sh
# still reaches a decision without a writable TMPDIR.
#
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASSWD_HOME="$(python3 -B -c 'import os, pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')"
ALLOWED=("PATH=${PATH:-/usr/bin:/bin}" "HOME=$PASSWD_HOME" "GH_CONFIG_DIR=$PASSWD_HOME/.config/gh")
for name in LANG LC_ALL TMPDIR SSH_AUTH_SOCK GH_TOKEN; do
  if [[ -n "${!name+set}" ]]; then
    ALLOWED+=("$name=${!name}")
  fi
done
DRIVER='
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
expected = {"lib/readiness_contract_v2.py", "lib/observer.py", "lib/readiness_contract.py", "lib/verification.py",
            "schemas/readiness-contract-v2.json", "contract-run.sh", "contract-run-v2.sh", "run-gates.sh",
            "merge-authority.sh", "prereq-check.sh", "migrate-handoff.sh", "northstar/handoff-write.sh"}
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
sys.exit(observer.main(sys.argv[2:]))
'
exec env -i "${ALLOWED[@]}" python3 -B -c "$DRIVER" "$HERE" "$@"
