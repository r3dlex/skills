// Asserts the checker's actual output against the required case table entry.
// Usage: node verify.mjs <case-plan.json> <tool-stdout-path> <exit>
import { readFileSync } from "node:fs";

function loadJson(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

function assertionValue(report, id) {
  return (report.assertions ?? []).filter((entry) => entry.id === id).map((entry) => entry.ok);
}

function checkReport(expect, report, failures) {
  if (expect.verdict !== undefined && report.verdict !== expect.verdict) {
    failures.push(`verdict ${JSON.stringify(report.verdict)} != ${JSON.stringify(expect.verdict)}`);
  }
  if (expect.observed_git !== undefined && report.observed.git !== expect.observed_git) {
    failures.push(`observed.git ${JSON.stringify(report.observed.git)} != ${JSON.stringify(expect.observed_git)}`);
  }
  if (expect.counts !== undefined && JSON.stringify(report.counts) !== JSON.stringify(expect.counts)) {
    failures.push(`counts ${JSON.stringify(report.counts)} != ${JSON.stringify(expect.counts)}`);
  }
  for (const [id, wanted] of Object.entries(expect.assertions ?? {})) {
    const values = assertionValue(report, id);
    if (values.length === 0) {
      failures.push(`assertion ${id} absent from report`);
    } else if (wanted === true && values.some((value) => value !== true)) {
      failures.push(`assertion ${id} not true everywhere: ${JSON.stringify(values)}`);
    } else if (wanted === false && !values.includes(false)) {
      failures.push(`assertion ${id} never false: ${JSON.stringify(values)}`);
    }
  }
}

function checkConsumer(expect, result, failures) {
  if (expect.consumer_readiness !== undefined && result.consumer_readiness !== expect.consumer_readiness) {
    failures.push(`consumer_readiness ${JSON.stringify(result.consumer_readiness)} != ${JSON.stringify(expect.consumer_readiness)}`);
  }
  const wanted = expect.consumer ?? {};
  if (wanted.failed !== undefined && JSON.stringify(result.failed) !== JSON.stringify(wanted.failed)) {
    failures.push(`failed ${JSON.stringify(result.failed)} != ${JSON.stringify(wanted.failed)}`);
  }
  if (wanted.failed_any !== undefined && !wanted.failed_any.some((id) => result.failed.includes(id))) {
    failures.push(`failed ${JSON.stringify(result.failed)} misses ${JSON.stringify(wanted.failed_any)}`);
  }
  for (const field of ["capture_authenticity", "live_remote_freshness"]) {
    if (wanted[field] !== undefined && result[field] !== wanted[field]) {
      failures.push(`${field} ${JSON.stringify(result[field])} != ${JSON.stringify(wanted[field])}`);
    }
  }
  if (wanted.fresh_git !== undefined && result.fresh_git !== wanted.fresh_git) {
    failures.push(`fresh_git ${JSON.stringify(result.fresh_git)} != ${JSON.stringify(wanted.fresh_git)}`);
  }
}

function main() {
  const [planPath, stdoutPath, exitText] = process.argv.slice(2);
  const plan = loadJson(planPath);
  const expect = plan.expect ?? {};
  const actual = Number.parseInt(exitText, 10);
  const failures = [];
  if (actual !== expect.exit) {
    failures.push(`exit ${actual} != ${expect.exit}`);
  }
  let output = "";
  try {
    output = readFileSync(stdoutPath, "utf8");
  } catch {
    failures.push("checker produced no stdout");
  }
  let parsed = null;
  if (output !== "") {
    try {
      parsed = JSON.parse(output);
    } catch {
      failures.push("stdout is not JSON");
    }
  }
  if (plan.kind === "consumer") {
    if (parsed !== null && parsed.schema !== "d13-consumer-check/1") {
      failures.push(`schema ${JSON.stringify(parsed.schema)} != d13-consumer-check/1`);
    }
    if (parsed !== null) {
      checkConsumer(expect, parsed, failures);
    }
  } else if (parsed !== null) {
    if (parsed.schema !== "d13-comparison/1") {
      failures.push(`schema ${JSON.stringify(parsed.schema)} != d13-comparison/1`);
    }
    checkReport(expect, parsed, failures);
  }
  if (failures.length > 0) {
    for (const failure of failures) {
      process.stdout.write(`    ${failure}\n`);
    }
    process.exit(1);
  }
  process.exit(0);
}

main();