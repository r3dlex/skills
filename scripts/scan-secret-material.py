#!/usr/bin/env -S python3 -I -B
# generated compat-shim — rendered from the python3 template; do not edit
import sys

if sys.flags.isolated != 1 or not sys.dont_write_bytecode:
    import posix
    posix.execv(sys.executable, [sys.executable, "-I", "-B", *sys.argv])

import os
import shutil
import subprocess

ALLOW = ["PATH","HOME","LANG","LC_ALL","TMPDIR"]
ENTRY_REL = "lib/leaf/scan-secret-material.mjs"


def refuse(code: str, status: int) -> None:
    sys.stderr.write(code + "\n")
    raise SystemExit(status)


here = os.path.dirname(os.path.abspath(__file__))
entry = os.path.join(here, ENTRY_REL)
if not os.path.isfile(entry):
    refuse("node_unavailable", 127)
node_bin = shutil.which("node")
if node_bin is None:
    refuse("node_unavailable", 127)
assert node_bin is not None
env = {name: os.environ[name] for name in ALLOW if name in os.environ}
probed = subprocess.run([node_bin, "--version"], check=False, capture_output=True, text=True, env=env)
if probed.returncode != 0:
    refuse("node_unavailable", 127)
if not probed.stdout.strip().startswith("v26."):
    refuse("node_version_unsupported", 126)
os.execve(node_bin, [node_bin, "--disable-proto=throw", entry, *sys.argv[1:]], env)
