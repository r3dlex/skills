#!/usr/bin/env bash
# Pinned local dependency only. Never search PATH or the network for a helper.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# readiness-contract/2 operation names route to their own pinned entry point.
# Every other name, including v1 admit/publish/migrate, stays on the v1 path below.
case "${1:-}" in
  admit-v2|publish-v2|approval-request|certify-v2|merge-v2|context-build|inventory-v1|audit-merges|export-evidence)
    exec bash "$HERE/contract-run-v2.sh" "$@" ;;
esac
# Pin check before the entry point loads. A mutated module must not be parsed first.
AUTOBAHN="$HERE" node --disable-proto=throw -e '
const {createHash} = require("node:crypto");
const {existsSync, readFileSync} = require("node:fs");
const {resolve} = require("node:path");
const root = process.env.AUTOBAHN;
const allowed = ["lib/engine.mjs", "lib/json.mjs", "lib/readiness_contract.mjs", "lib/verification.mjs"];
function fail(error) {
  const message = error instanceof Error ? error.message : String(error);
  process.stdout.write(JSON.stringify({
    authority_verification: "external-required",
    dispatch_authorized: false,
    error: "dependency_failed:" + message,
    execution_ready: false,
  }, null, 2) + "\n");
  process.exit(1);
}
function canon(value) {
  if (Array.isArray(value)) return "[" + value.map(canon).join(",") + "]";
  if (value && typeof value === "object") {
    return "{" + Object.keys(value).sort().map((key) => JSON.stringify(key) + ":" + canon(value[key])).join(",") + "}";
  }
  return JSON.stringify(value);
}
try {
  const manifest = JSON.parse(readFileSync(resolve(root, "readiness-dependency.json"), "utf8"));
  let peer = resolve(root, "../northstar");
  if (!existsSync(peer)) peer = resolve(root, "../../02-govern-plan/northstar");
  const peerManifest = JSON.parse(readFileSync(resolve(peer, "readiness-dependency.json"), "utf8"));
  if (canon(peerManifest) !== canon(manifest)) throw new Error("producer/consumer fingerprint mismatch");
  if (manifest.schema !== "readiness-contract/1") throw new Error("unsupported helper release");
  const files = manifest.files || {};
  for (const [name, expected] of Object.entries(files)) {
    if (!allowed.includes(name)) throw new Error("unsupported helper dependency");
    const digest = createHash("sha256").update(readFileSync(resolve(root, name))).digest("hex");
    if (digest !== expected) throw new Error("helper fingerprint mismatch");
  }
  if (Object.keys(files).sort().join("\n") !== allowed.slice().sort().join("\n")) throw new Error("incomplete helper dependency");
} catch (error) {
  fail(error);
}
'
exec node --disable-proto=throw "$HERE/lib/readiness_contract.mjs" "$@"
