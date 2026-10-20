#!/usr/bin/env node
// Synthetic mutation only: forward real Git bytes, never invent its response.
const { spawnSync } = require("node:child_process");
const { existsSync, readFileSync, realpathSync, writeFileSync } = require("node:fs");
const config = JSON.parse(process.env.D13_SYNTHETIC_GIT_MOVE);
const argv = process.argv.slice(2);
if (realpathSync(process.cwd()) === config.root && JSON.stringify(argv) === JSON.stringify(config.trigger)) {
  const count = existsSync(config.state) ? JSON.parse(readFileSync(config.state)).count + 1 : 1;
  if (count === 2) {
    const moved = spawnSync(config.git, ["update-ref", config.ref, config.to], { encoding: "utf8" });
    if (moved.status !== 0) throw new Error(moved.stderr);
  }
  writeFileSync(config.state, JSON.stringify({ count, moved: count >= 2, ref: config.ref, to: config.to }));
}
const result = spawnSync(config.git, argv, { maxBuffer: 64 * 1024 * 1024 });
process.stdout.write(result.stdout ?? "");
process.stderr.write(result.stderr ?? "");
process.exitCode = result.status ?? 127;
