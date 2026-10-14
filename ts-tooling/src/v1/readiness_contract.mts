import { existsSync, readFileSync, realpathSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { digest, dumps } from "./json.mjs";
import { main } from "./engine.mjs";

export { Invalid, VERSION, ID, SHA, REVISION, canonical, dumps, read, require, string } from "./json.mjs";
export type { Args } from "./json.mjs";
export { validate, VerificationError } from "./verification.mjs";

const ALLOWED = ["lib/engine.mjs", "lib/json.mjs", "lib/readiness_contract.mjs", "lib/verification.mjs"];

function dependencyFailed(error: unknown): never {
  const message = error instanceof Error ? error.message : String(error);
  process.stdout.write(dumps({
    error: "dependency_failed:" + message,
    dispatch_authorized: false,
    execution_ready: false,
    authority_verification: "external-required",
  }) + "\n");
  process.exit(1);
}

function peerManifest(autobahn: string): unknown {
  let peer = resolve(autobahn, "../northstar");
  if (!existsSync(peer)) {
    peer = resolve(autobahn, "../../02-govern-plan/northstar");
  }
  return JSON.parse(readFileSync(resolve(peer, "readiness-dependency.json"), "utf8"));
}

function checkFile(autobahn: string, name: string, expected: string): void {
  if (!ALLOWED.includes(name)) {
    throw new Error("unsupported helper dependency");
  }
  if (digest(resolve(autobahn, name)) !== expected) {
    throw new Error("helper fingerprint mismatch");
  }
}

function checkPins(autobahn: string): void {
  try {
    const manifest = JSON.parse(readFileSync(resolve(autobahn, "readiness-dependency.json"), "utf8")) as { schema?: string; files?: Record<string, string> };
    if (dumps(peerManifest(autobahn), null, true, true) !== dumps(manifest, null, true, true)) {
      throw new Error("producer/consumer fingerprint mismatch");
    }
    if (manifest.schema !== "readiness-contract/1") {
      throw new Error("unsupported helper release");
    }
    const files = manifest.files ?? {};
    for (const [name, expected] of Object.entries(files)) {
      checkFile(autobahn, name, expected);
    }
    if (Object.keys(files).sort().join("\n") !== [...ALLOWED].sort().join("\n")) {
      throw new Error("incomplete helper dependency");
    }
  } catch (error) {
    dependencyFailed(error);
  }
}

function invokedDirectly(): boolean {
  const entry = process.argv[1];
  if (!entry) {
    return false;
  }
  return realpathSync(entry) === realpathSync(new URL(import.meta.url).pathname);
}

if (invokedDirectly()) {
  const major = Number((process.versions.node ?? "").split(".")[0]);
  if (major !== 26) {
    process.stderr.write("node_version_unsupported\n");
    process.exit(126);
  }
  checkPins(dirname(dirname(fileURLToPath(import.meta.url))));
    process.exit(main(process.argv.slice(2)));
}

