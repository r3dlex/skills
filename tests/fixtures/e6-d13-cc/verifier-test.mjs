// A matching exit alone must never make a missing result envelope pass.
import { spawnSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import { join } from "node:path";
const [verifier, work] = process.argv.slice(2);
const plan = join(work, "verifier-plan.json");
const output = join(work, "verifier-output.txt");
writeFileSync(plan, JSON.stringify({ case: "verifier-self-test", kind: "consumer", expect: { exit: 1 } }));
const env = { ...process.env }; delete env.D13_CASE_RECEIPT;
for (const bytes of ["", "null\n"]) {
  writeFileSync(output, bytes);
  const result = spawnSync(process.execPath, [verifier, plan, output, "1"], { env });
  if (result.status !== 1 || !result.stdout.toString().includes("result envelope absent")) throw new Error(`invalid result envelope not explicitly rejected (verifier exit ${result.status})`);
}
