// Always execute the actual CLI. Optional environment is solely for a fixture
// wrapper that moves a real disposable Git ref between the two required reads.
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
const [planPath, tool, index] = process.argv.slice(2);
const plan = JSON.parse(readFileSync(planPath, "utf8"));
const check = index === undefined ? null : plan.checks[Number(index)];
const args = check ? ["--consumer-check", check.evidence] : [plan.run, ...(plan.kind === "observe" ? ["--observe"] : [])];
const result = spawnSync(process.execPath, [tool, ...args], { cwd: check?.cwd ?? process.cwd(), env: { ...process.env, ...(check?.env ?? plan.env ?? {}) }, maxBuffer: 64 * 1024 * 1024 });
process.stdout.write(result.stdout ?? "");
process.stderr.write(result.stderr ?? "");
process.exitCode = result.status ?? 127;
