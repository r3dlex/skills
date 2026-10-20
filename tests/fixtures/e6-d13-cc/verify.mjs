// Asserts the checker's actual output against the required case table entry.
// Usage: node verify.mjs <case-plan.json> <tool-stdout-path> <exit>
import { appendFileSync, readFileSync } from "node:fs";
import { createHash } from "node:crypto";

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
  for (const id of wanted.failed_all ?? []) {
    if (!result.failed?.includes(id)) failures.push(`required failure ${id} absent: ${JSON.stringify(result.failed)}`);
  }
  for (const field of ["capture_authenticity", "live_remote_freshness", "consumer_readiness"]) {
    if (wanted[field] !== undefined && result[field] !== wanted[field]) {
      failures.push(`${field} ${JSON.stringify(result[field])} != ${JSON.stringify(wanted[field])}`);
    }
  }
  if (wanted.fresh_git !== undefined && result.fresh_git !== wanted.fresh_git) {
    failures.push(`fresh_git ${JSON.stringify(result.fresh_git)} != ${JSON.stringify(wanted.fresh_git)}`);
  }
}

function readResult(stdoutPath, failures) {
  let output = "";
  try {
    output = readFileSync(stdoutPath, "utf8");
  } catch {
    failures.push("checker produced no stdout");
  }
  let parsed = null;
  if (output === "") failures.push("checker produced empty stdout");
  if (output !== "") {
    try {
      parsed = JSON.parse(output);
    } catch {
      failures.push("stdout is not JSON");
    }
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) failures.push("result envelope absent");
  return { output, parsed };
}

function checkResult(plan, expect, parsed, failures) {
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
}

function checkMovement(plan, failures) {
  let movement;
  const config = plan.environment?.D13_SYNTHETIC_GIT_MOVE ?? plan.env?.D13_SYNTHETIC_GIT_MOVE;
  if (config) {
    movement = loadJson(JSON.parse(config).state);
    if (movement.moved !== true || movement.count < 2) failures.push("fixture did not actually move its Git ref between reads");
  }
  return movement;
}

function main() {
  const [planPath, stdoutPath, exitText] = process.argv.slice(2);
  const plan = loadJson(planPath);
  const expect = plan.expect ?? {};
  const actual = Number.parseInt(exitText, 10);
  const failures = [];
  if (actual !== expect.exit) failures.push(`exit ${actual} != ${expect.exit}`);
  const { output, parsed } = readResult(stdoutPath, failures);
  checkResult(plan, expect, parsed, failures);
  const movement = checkMovement(plan, failures);
  if (failures.length > 0) {
    for (const failure of failures) {
      process.stdout.write(`    ${failure}\n`);
    }
  }
  if (process.env.D13_CASE_RECEIPT) appendFileSync(process.env.D13_CASE_RECEIPT, `${JSON.stringify({ case: plan.case, label: plan.label, exit: actual, expected_exit: expect.exit, verdict: parsed?.verdict, assertions: parsed?.assertions, failed: parsed?.failed, movement, checks: failures, stdout_sha256: createHash("sha256").update(output).digest("hex") })}\n`);
  process.exit(failures.length > 0 ? 1 : 0);
}

main();
