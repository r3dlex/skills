// Case table for the D13 comparison contract checker: P1, M01-M34, O01-O09,
// C01-C15. `assertions` maps a required assertion id to its required `ok`
// value; `exit` is the exact required process exit code.
export const CASE_TABLE = [
  {
    id: "P1",
    kind: "report",
    note: "four required targets, skills distinct lanes, both consumers source-lane, one qualifying audit pair per target",
    expect: {
      assertions: { "observe-git": true, "projection-equal": true, "stderr-equal": true, "written-equal": true, "common-dir-reference": true, "common-dir-candidate": true, "lane-observed-per-target": true, "audit-pair-per-target": true, "registry-bound": true, "site-set": true, "raw-inputs-bound": true, "captures-serialized": true, "order-audits-before-exports": true, "log-quiescent": true },
      counts: { equal_refusal: 4, equal_success: 12, red: 0, sites: 16 },
      exit: 0,
      observed_git: true,
      verdict: "pass",
    },
  },
  { id: "M01", kind: "report", mutations: ["M01"], expect: { assertions: { "projection-equal": false }, exit: 1, verdict: "red" } },
  { id: "M02", kind: "report", mutations: ["M02"], expect: { assertions: { "provenance-expected": false }, exit: 1, verdict: "red" } },
  { id: "M03", kind: "report", mutations: ["M03"], expect: { assertions: { "lanes-distinct-own-repository": false }, exit: 1, verdict: "red" } },
  { id: "M04", kind: "report", mutations: ["M04"], expect: { assertions: { "provenance-expected": false }, exit: 1, verdict: "red" } },
  { id: "M05", kind: "report", mutations: ["M05"], expect: { assertions: { "exit-equal": false }, exit: 1, verdict: "red" } },
  { id: "M06", kind: "report", mutations: ["M06"], expect: { assertions: { "refusal-codes-equal": false }, exit: 1, verdict: "red" } },
  { id: "M07", kind: "report", mutations: ["M07"], expect: { assertions: { "site-set": false }, exit: 1, verdict: "red" } },
  { id: "M08", kind: "report", mutations: ["M08"], expect: { assertions: { "projection-equal": false }, exit: 1, verdict: "red" } },
  { id: "M09", kind: "report", mutations: ["M09"], expect: { exit: 2, verdict: "malformed" } },
  { id: "M10", kind: "report", mutations: ["M10"], expect: { assertions: { "common-dir-candidate": false }, exit: 1, verdict: "red" } },
  { id: "M11", kind: "report", mutations: ["M11"], expect: { assertions: { "stderr-equal": false }, exit: 1, verdict: "red" } },
  { id: "M12", kind: "report", mutations: ["M12"], expect: { assertions: { "written-equal": false }, exit: 1, verdict: "red" } },
  { id: "M13", kind: "report", mutations: ["M13"], expect: { assertions: { "order-audits-before-exports": false }, exit: 1, verdict: "red" } },
  { id: "M14", kind: "report", mutations: ["M14"], expect: { assertions: { "log-quiescent": false }, exit: 1, verdict: "red" } },
  { id: "M15", kind: "report", mutations: ["M15"], expect: { assertions: { "provenance-pair": false }, exit: 1, verdict: "red" } },
  { id: "M16", kind: "report", mutations: ["M16"], expect: { assertions: { "lane-observed-per-target": false }, exit: 1, verdict: "red" } },
  { id: "M17", kind: "report", mutations: ["M17"], expect: { exit: 2, verdict: "malformed" } },
  { id: "M18", kind: "report", mutations: ["M18"], expect: { assertions: { "projection-unique": false }, exit: 1, verdict: "red" } },
  { id: "M19", kind: "report", mutations: ["M19"], expect: { assertions: { "target-revision": false }, exit: 1, verdict: "red" } },
  { id: "M20", kind: "report", mutations: ["M20"], expect: { assertions: { "envelope-schema": false }, exit: 1, verdict: "red" } },
  { id: "M21", kind: "report", mutations: ["M21"], expect: { assertions: { "finding-codes-equal": false }, exit: 1, verdict: "red" } },
  { id: "M22", kind: "report", mutations: ["M22"], expect: { assertions: { "common-dir-reference": false }, exit: 1, verdict: "red" } },
  { id: "M23", kind: "report", mutations: ["M23"], expect: { assertions: { "driver-commits-distinct": false }, exit: 1, verdict: "red" } },
  { id: "M24", kind: "report", mutations: ["M24"], expect: { assertions: { "projection-equal": false }, exit: 1, verdict: "red" } },
  { id: "M25", kind: "report", mutations: ["M25"], expect: { exit: 2, verdict: "malformed" } },
  { id: "M26", kind: "report", mutations: ["M26"], expect: { exit: 2, verdict: "malformed" } },
  { id: "M27", kind: "report", mutations: ["M27"], expect: { assertions: { "targets-complete": false }, exit: 1, verdict: "red" } },
  { id: "M28", kind: "report", mutations: ["M28"], expect: { assertions: { "envelope-operation": false }, exit: 1, verdict: "red" } },
  { id: "M29", kind: "report", mutations: ["M29"], expect: { assertions: { "envelope-plan": false }, exit: 1, verdict: "red" } },
  { id: "M30", kind: "report", mutations: ["M30"], expect: { assertions: { "capture-argv": false }, exit: 1, verdict: "red" } },
  { id: "M31", kind: "report", mutations: ["M31"], expect: { assertions: { "log-quiescent": false }, exit: 1, verdict: "red" } },
  { id: "M32", kind: "report", mutations: ["M32"], expect: { assertions: { "captures-serialized": false }, exit: 1, verdict: "red" } },
  { id: "M33", kind: "report", mutations: ["M33"], expect: { assertions: { "written-equal": false }, exit: 1, verdict: "red" } },
  { id: "M34", kind: "report", mutations: ["M34"], expect: { assertions: { "projection-unique": false }, exit: 1, verdict: "red" } },
  { id: "O01", kind: "observe", expect: { assertions: { "observe-git": true, "common-dir-candidate": true }, exit: 0, observed_git: true, verdict: "pass" } },
  { id: "O02", kind: "observe", world: { linkedCandidate: true }, expect: { assertions: { "observe-git": true, "common-dir-candidate": false }, exit: 1, observed_git: true, verdict: "red" } },
  { id: "O03", kind: "observe", mutations: ["O03"], expect: { assertions: { "observe-git": false }, exit: 1, observed_git: false, verdict: "red" } },
  { id: "O04", kind: "observe", world: { repoPlans: 3 }, run: { registryPlans: 2 }, expect: { assertions: { "registry-bound": false }, exit: 1, verdict: "red" } },
  { id: "O05", kind: "observe", run: { olderRevision: "skills", runPlans: 1 }, expect: { assertions: { "target-ref-bound": false }, exit: 1, verdict: "red" } },
  { id: "O06", kind: "observe", world: { policyRepository: "skills", wrongPolicyRepository: "other-root" }, expect: { assertions: { "target-repository-bound": false }, exit: 1, verdict: "red" } },
  { id: "O07", kind: "observe", observation: { finishRevision: true }, expect: { assertions: { "target-ref-bound": false }, exit: 1, verdict: "red" } },
  { id: "O08", kind: "observe", mutations: ["O08"], expect: { assertions: { "audit-pair-per-target": false }, exit: 1, verdict: "red" } },
  { id: "O09", kind: "observe", world: { repoPlans: 3 }, run: { dropRepository: "aitool-root", dropSites: ["export-evidence"], registryPlans: 2 }, expect: { assertions: { "registry-bound": false, "site-set": false }, exit: 1, verdict: "red" } },
  { id: "C01", kind: "consumer", expect: { consumer: { capture_authenticity: "unverified", consumer_readiness: "unready", failed: [], live_remote_freshness: "unverified" }, exit: 0 } },
  { id: "C02", kind: "consumer", consumer: { dropContract: true }, expect: { exit: 2 } },
  { id: "C03", kind: "consumer", consumer: { redRun: true }, expect: { consumer: { failed_all: ["raw-report-recomputation"] }, exit: 1 } },
  { id: "C04", kind: "consumer", consumer: { wrongToolSha: true }, expect: { consumer: { failed: ["dependency-tool"] }, exit: 1 } },
  { id: "C05", kind: "consumer", consumer: { wrongSpecDigest: true }, expect: { consumer: { failed: ["dependency-spec"] }, exit: 1 } },
  { id: "C06", kind: "consumer", consumer: { forgedReport: true }, expect: { consumer: { failed_all: ["report-consistency", "raw-report-recomputation"] }, exit: 1 } },
  { id: "C07", kind: "consumer", consumer: { tamperedReport: true }, expect: { consumer: { failed_all: ["report-consistency"] }, exit: 1 } },
  { id: "C08", kind: "consumer", consumer: { rawDrift: true }, expect: { consumer: { failed_all: ["raw-inputs-bound"] }, exit: 1 } },
  { id: "C09", kind: "consumer", consumer: { wrongGeneration: true }, expect: { consumer: { failed: ["dependency-generation"] }, exit: 1 } },
  { id: "C10", kind: "consumer", consumer: { unrelatedMerge: true }, expect: { consumer: { failed_all: ["dependency-ancestry", "dependency-completion"] }, exit: 1 } },
  { id: "C11", kind: "consumer", consumer: { unavailableHistory: true }, expect: { consumer: { failed: ["dependency-history-unavailable"] }, exit: 1 } },
  { id: "C12", kind: "consumer", consumer: { oldCaptureHead: true }, expect: { consumer: { failed_all: ["consumer-head-binding"] }, exit: 1 } },
  { id: "C13", kind: "consumer", consumer: { relocate: true }, expect: { consumer: { capture_authenticity: "unverified", consumer_readiness: "unready", failed: [], fresh_git: false, live_remote_freshness: "unverified" }, exit: 0 } },
  { id: "C14", kind: "consumer", consumer: { noIndependentReceipts: true }, expect: { consumer: { capture_authenticity: "unverified", consumer_readiness: "unready", failed: [], live_remote_freshness: "unverified" }, exit: 0 } },
  { id: "C15", kind: "consumer", consumer: { presentFails: true }, expect: { consumer: { failed_all: ["report-consistency"] }, exit: 1 } },
];

// Cure regressions extend (never replace) the 59 contract cases. The named
// assertion is mandatory even when the mutation also exposes another failure.
const rawRegressions = [
  ["R01", "envelope-schema", "invalid UTF-8 outside the removed span"],
  ["R02", "projection-unique", "escaped provenance key and nonliteral colon spacing"],
  ["R03", "projection-unique", "duplicate schema, inconvenient final schema"],
  ["R04", "projection-unique", "duplicate nonprovenance depth-one findings"],
  ["R05", "envelope-schema", "NaN literal in generic refusal"],
  ["R06", "raw-inputs-bound", "unmapped changed refusal snapshot"],
  ["R07", "written-equal", "empty successful exports, including snapshot directories"],
  ["R08", "raw-inputs-bound", "declared maps empty but retained snapshots nonempty"],
  ["R09", "observe-git", "nonexistent claimed target root, real transcript cwd"],
  ["R10", "target-ref-bound", "forbidden local main ref, genuinely observed"],
  ["R11", "observe-git", "wrong transcript lanes digest"],
  ["R12", "observe-git", "wrong transcript cwd"],
  ["R13", "observe-git", "stderr byte drift in retained Git response"],
  ["R14", "captures-serialized", "invalid UTC intervals"],
  ["R15", "envelope-plan", "wrong present audit generation"],
  ["R16", "refusal-exit", "generic refusal with zero exits"],
  ["R17", "raw-inputs-bound", "deleted snapshot omitted from its map"],
];
for (const [id, assertion, note] of rawRegressions) {
  CASE_TABLE.push({ id, kind: id === "R09" || id === "R10" || id === "R13" ? "observe" : "report", mutations: [id], note, expect: { assertions: { [assertion]: false }, exit: 1, verdict: "red" } });
}
CASE_TABLE.push({ id: "R18", kind: "report", mutations: ["R18"], note: "invalid export log sample types", expect: { exit: 2, verdict: "malformed" } });
CASE_TABLE.push({ id: "R19", kind: "report", mutations: ["R19"], note: "noncanonical base64 response", expect: { exit: 2, verdict: "malformed" } });
CASE_TABLE.push({ id: "R20", kind: "report", mutations: ["R20"], note: "valid multibyte bytes before the removed span remain exact", expect: { exit: 0, verdict: "pass" } });
CASE_TABLE.push({ id: "R21", kind: "observe", world: {}, note: "real private target ref moves between direct start/finish reads", expect: { assertions: { "target-ref-bound": false, "observe-git": false }, exit: 1, verdict: "red" } });
CASE_TABLE.push({ id: "R22", kind: "report", mutations: ["R22"], note: "extra metadata input, inventoried rather than unlisted", expect: { assertions: { "raw-inputs-bound": false }, exit: 1, verdict: "red" } });
CASE_TABLE.push({ id: "R23", kind: "observe", mutations: ["R23"], note: "nonexistent candidate root, accurate transcript at real root", expect: { assertions: { "observe-git": false }, exit: 1, verdict: "red" } });
CASE_TABLE.push({ id: "R24", kind: "report", mutations: ["R24"], note: "invalid export map digest type", expect: { exit: 2, verdict: "malformed" } });
CASE_TABLE.push({ id: "R25", kind: "report", mutations: ["R25"], note: "audit fields must be null, not export samples", expect: { exit: 2, verdict: "malformed" } });
CASE_TABLE.push({ id: "R26", kind: "report", mutations: ["R26"], note: "unmapped __proto__ snapshot cannot disappear into an object prototype", expect: { assertions: { "raw-inputs-bound": false }, exit: 1, verdict: "red" } });
CASE_TABLE.push({ id: "R27", kind: "observe", mutations: ["R27"], note: "non-main targets also require literal fully-qualified refs", expect: { assertions: { "target-ref-bound": false }, exit: 1, verdict: "red" } });

const consumerRegressions = [
  ["D01", "headBeforePublication", "consumer-head-binding", 1],
  ["D02", "headToolDrift", "consumer-head-binding", 1],
  ["D03", "captureMismatch", "consumer-head-binding", 1],
  ["D04", "driverDrift", "consumer-head-binding", 1],
  ["D05", "corruptGraph", "dependency-generation", 1],
  ["D06", "counterfeitSpec", "dependency-spec", 1],
  ["D07", "arbitraryGeneration", "dependency-generation", 1],
  ["D08", "wrongRegistryId", "dependency-registry", 1],
  ["D09", "wrongPolicy", "dependency-generation", 1],
  ["D10", "missingArtifacts", "dependency-generation", 1],
  ["D11", "missingReceipts", "input-shape", 2],
  ["D12", "missingCompletionFields", "input-shape", 2],
  ["D13", "wrongCompletion", "dependency-completion", 1],
  ["D14", "captureAsPrHead", "dependency-completion", 1],
  ["D15", "wrongPlan", "dependency-completion", 1],
  ["D16", "symlinkRun", "input-shape", 2],
  ["D17", "outsideScopeRun", "input-shape", 2],
  ["D18", "symlinkReceipt", "input-shape", 2],
  ["D19", "receiptDrift", "retained-receipts-bound", 1],
  ["D20", "headRegistrationDrift", "consumer-head-binding", 1],
  ["D21", "otherValidGeneration", "dependency-generation", 1],
  ["D22", "missingSidecar", "dependency-generation", 1],
  ["D23", "headMoves", "consumer-head-binding", 1],
  ["D24", "targetMoves", "consumer-head-binding", 1],
  ["D25", "prePublicationCollection", "dependency-completion", 1],
  ["D26", "wrongToolBlob", "dependency-tool", 1],
  ["D27", "missingToolBlob", "input-shape", 2],
  ["D28", "missingReceiptFile", "input-shape", 2],
];
for (const [id, option, failure, exit] of consumerRegressions) {
  CASE_TABLE.push({ id, kind: "consumer", consumer: { [option]: true }, note: option, expect: { consumer: { failed_all: [failure] }, exit } });
}

export function findCase(id) {
  const found = CASE_TABLE.find((entry) => entry.id === id);
  if (found === undefined) {
    throw new Error(`unknown fixture case ${id}`);
  }
  return found;
}
