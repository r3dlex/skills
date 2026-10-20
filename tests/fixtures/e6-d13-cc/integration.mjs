// Exercise the same consumer-file loop used by the discovered Bash suite.
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
const plan = JSON.parse(readFileSync(process.argv[2], "utf8"));
for (const [state, cwd] of Object.entries(plan.suite_checks ?? {})) {
  const result = spawnSync("bash", ["tests/e6_d13_comparison_test.sh", "--consumer-files-only"], { cwd, encoding: "utf8" });
  const expected = state === "present" ? 1 : 0;
  const marker = state === "present" ? "FAIL: consumer" : "ABSENT: consumer";
  if (result.status !== expected || !result.stdout.includes(marker)) {
    process.stderr.write(`${state}: exit=${result.status}, expected=${expected}\n${result.stdout}${result.stderr}`);
    process.exit(1);
  }
}
