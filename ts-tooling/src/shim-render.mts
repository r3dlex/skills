import { assertNodeVersion } from "./node-version.mjs";
import { invokedDirectly } from "./invoked.mjs";

assertNodeVersion();

export const NODE_FLAGS = ["--disable-proto=throw"] as const;
export const PYTHON_FLAGS = ["-I", "-B"] as const;
export const BASE_ALLOW = ["PATH", "HOME", "LANG", "LC_ALL", "TMPDIR"] as const;
const NAME = /^[A-Za-z_][A-Za-z0-9_]*$/;

export class ShimRenderError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ShimRenderError";
  }
}

export function assertAllowNames(names: readonly string[]): void {
  for (const name of names) {
    if (!NAME.test(name) || name.startsWith("NODE_")) {
      throw new ShimRenderError(`allowlist name refused: ${name}`);
    }
  }
}

function allowLines(names: readonly string[]): string[] {
  return names.map(
    (name) => `if [[ "\${${name}+x}" == x ]]; then env_args+=("${name}=$${name}"); fi`,
  );
}

export function renderBash(entrypoint: string, names: readonly string[]): string {
  assertAllowNames(names);
  const allows = [...BASE_ALLOW, ...names];
  const lines = [
    "#!/usr/bin/env bash",
    "# generated compat-shim — rendered from the bash template; do not edit",
    "set -euo pipefail",
    'here="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"',
    `entry="$here/${entrypoint}"`,
    'if [[ ! -f "$entry" ]]; then',
    "\tprintf 'node_unavailable\\n' >&2",
    "\texit 127",
    "fi",
    'node_bin="$(command -v node 2>/dev/null || true)"',
    'if [[ -z "$node_bin" ]]; then',
    "\tprintf 'node_unavailable\\n' >&2",
    "\texit 127",
    "fi",
    'if ! version="$("$node_bin" --version 2>/dev/null)"; then',
    "\tprintf 'node_unavailable\\n' >&2",
    "\texit 127",
    "fi",
    'case "$version" in',
    "v26.*)",
    "\t;;",
    "*)",
    "\tprintf 'node_version_unsupported\\n' >&2",
    "\texit 126",
    "\t;;",
    "esac",
    "env_args=()",
    ...allowLines(allows),
    'if [[ ${#env_args[@]} -gt 0 ]]; then',
    '\texec /usr/bin/env -i "${env_args[@]}" "$node_bin" --disable-proto=throw "$entry" "$@"',
    "fi",
    'exec /usr/bin/env -i "$node_bin" --disable-proto=throw "$entry" "$@"',
    "",
  ];
  return lines.join("\n");
}

function pythonAllow(names: readonly string[]): string {
  return JSON.stringify([...BASE_ALLOW, ...names]);
}

export function renderPython(entrypoint: string, names: readonly string[]): string {
  assertAllowNames(names);
  const allow = pythonAllow(names);
  return `#!/usr/bin/env -S python3 -I -B
# generated compat-shim — rendered from the python3 template; do not edit
import os
import shutil
import subprocess
import sys

if sys.flags.isolated != 1 or not sys.dont_write_bytecode:
    os.execv(sys.executable, [sys.executable, "-I", "-B", *sys.argv])

ALLOW = ${allow}
ENTRY_REL = ${JSON.stringify(entrypoint)}


def refuse(code, status):
    sys.stderr.write(code + "\\n")
    raise SystemExit(status)


here = os.path.dirname(os.path.abspath(__file__))
entry = os.path.join(here, ENTRY_REL)
if not os.path.isfile(entry):
    refuse("node_unavailable", 127)
node_bin = shutil.which("node")
if not node_bin:
    refuse("node_unavailable", 127)
probed = subprocess.run([node_bin, "--version"], check=False, capture_output=True, text=True)
if probed.returncode != 0:
    refuse("node_unavailable", 127)
if not probed.stdout.strip().startswith("v26."):
    refuse("node_version_unsupported", 126)
env = {name: os.environ[name] for name in ALLOW if name in os.environ}
os.execve(node_bin, [node_bin, "--disable-proto=throw", entry, *sys.argv[1:]], env)
`;
}

export function main(argv: readonly string[]): number {
  const kind = argv[0];
  const entrypoint = argv[1];
  if (kind !== "bash" && kind !== "python3") {
    process.stderr.write("usage: shim-render <bash|python3> <entrypoint> [names...]\n");
    return 2;
  }
  if (entrypoint === undefined || entrypoint.includes("..") || entrypoint.startsWith("/")) {
    process.stderr.write("entrypoint refused\n");
    return 2;
  }
  const names = argv.slice(2);
  try {
    const text = kind === "bash" ? renderBash(entrypoint, names) : renderPython(entrypoint, names);
    process.stdout.write(text);
    return 0;
  } catch (error) {
    const message = error instanceof Error ? error.message : "shim_render_failed";
    process.stderr.write(`${message}\n`);
    return 1;
  }
}

if (invokedDirectly(import.meta.url)) {
  process.exit(main(process.argv.slice(2)));
}
