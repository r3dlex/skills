import assert from "node:assert/strict";
import { main, type SampleDeps } from "../src/sample.mjs";
import { nodeVersionStatus } from "../src/node-version.mjs";

const out: string[] = [];
const err: string[] = [];
const deps: SampleDeps = {
  read: () => "from-seam\n",
  writeOut: (text) => {
    out.push(text);
  },
  writeErr: (text) => {
    err.push(text);
  },
};

assert.equal(main(["read", "ignored"], deps), 0);
assert.equal(out.join(""), "from-seam\n");
assert.equal(main([], deps), 0);
assert.equal(nodeVersionStatus("18.0.0"), "node_version_unsupported");
assert.equal(nodeVersionStatus("26.11.1"), "ok");
process.stdout.write("sample seam ok\n");
