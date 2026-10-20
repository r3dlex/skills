// Mutation helpers. Each mutation changes exactly one documented semantic
// feature of the synthetic base run so the required assertion is the one that
// turns red.
import {
  PLANS,
  REFUSAL_CODES,
  REPOS,
  envelopeFor,
  findSite,
  pretty,
  sha256,
  siteKey,
} from "./world.mjs";

const AUDIT = "audit-merges";
const EXPORT = "export-evidence";

function reRender(site, overrides) {
  site.stdout = Buffer.from(pretty(envelopeFor(site.world, site, overrides)), "utf8");
}

function withWorld(model, site) {
  return { ...site, world: model.world };
}

function lineOf(text, needle) {
  const index = text.indexOf(needle);
  if (index < 0) {
    throw new Error(`fixture envelope lacks ${needle}`);
  }
  const start = text.lastIndexOf("\n", index - 1) + 1;
  const end = text.indexOf("\n", index);
  return { start, end: end + 1, line: text.slice(start, end + 1) };
}

function rewriteStdout(site, transform) {
  site.stdout = Buffer.from(transform(site.stdout.toString("utf8")), "utf8");
}

function dropWritten(site, phase, path) {
  const files = site.files[phase];
  const target = files[path];
  delete files[path];
  delete site.meta[phase === "before" ? "written_before" : "written"][path];
  return target;
}

export const MUTATIONS = {
  M01: (model) => {
    const site = withWorld(model, findSite(model, `candidate/skills/${PLANS[0]}/${EXPORT}`));
    reRender(site, { log_sha256: sha256("M01 drift") });
    model.sites[model.sites.indexOf(findSite(model, siteKey(site)))] = site;
  },
  M02: (model) => {
    const site = findSite(model, `candidate/skills/${PLANS[0]}/${AUDIT}`);
    rewriteStdout(site, (text) => {
      const line = lineOf(text, '"provenance"');
      return text.slice(0, line.start) + text.slice(line.end);
    });
  },
  M03: (model) => {
    for (const operation of [AUDIT, EXPORT]) {
      const site = withWorld(model, findSite(model, `candidate/skills/${PLANS[0]}/${operation}`));
      reRender(site, { provenance: "base-copy" });
      replace(model, site);
    }
  },
  M04: (model) => {
    const reference = withWorld(model, findSite(model, `reference/skills/${PLANS[0]}/${AUDIT}`));
    reRender(reference, { provenance: "source-lane" });
    replace(model, reference);
    const candidate = withWorld(model, findSite(model, `candidate/skills/${PLANS[0]}/${AUDIT}`));
    reRender(candidate, { provenance: "base-copy" });
    replace(model, candidate);
  },
  M05: (model) => {
    const site = findSite(model, `candidate/skills/${PLANS[0]}/${AUDIT}`);
    site.exit = 1;
    site.meta.exit = 1;
  },
  M06: (model) => {
    const site = withWorld(model, findSite(model, `candidate/ai-factory/${PLANS[0]}/${EXPORT}`));
    reRender(site, { code: "evidence_unknown" });
    replace(model, site);
  },
  M07: (model) => {
    model.sites = model.sites.filter((site) => siteKey(site) !== `candidate/ai-catapult/${PLANS[0]}/${EXPORT}`);
  },
  M08: (model) => {
    const site = withWorld(model, findSite(model, `candidate/skills/${PLANS[0]}/${AUDIT}`));
    reRender(site, { merged_at: "2026-10-19T12:00:06Z" });
    replace(model, site);
  },
  M09: (model) => {
    model.normalizations = [{ class: "time-field", site: "/refusals/0/detail" }];
  },
  M10: (model) => {
    model.lanes.candidate.common_dir = model.lanes.targets.find((target) => target.repository === "aitool-root").common_dir;
  },
  M11: (model) => {
    const site = findSite(model, `candidate/skills/${PLANS[0]}/${AUDIT}`);
    site.stderr = Buffer.concat([site.stderr, Buffer.from("synthetic stderr drift\n", "utf8")]);
  },
  M12: (model) => {
    const site = findSite(model, `candidate/skills/${PLANS[0]}/${EXPORT}`);
    const path = "evidence/exports/plan.json";
    const bytes = Buffer.from("M12 written drift\n", "utf8");
    site.files.after[path] = bytes;
    site.meta.written[path] = sha256(bytes);
  },
  M13: (model) => {
    const audit = findSite(model, `candidate/skills/${PLANS[0]}/${AUDIT}`);
    const exports = model.sites.filter((site) => site.operation === EXPORT).sort((left, right) => left.meta.sequence - right.meta.sequence);
    const gapStart = new Date(Date.parse(exports[1].meta.started_at) - 30000).toISOString().replace(".000", "");
    audit.meta.started_at = gapStart;
    audit.meta.finished_at = new Date(Date.parse(gapStart) + 5000).toISOString().replace(".000", "");
    resequence(model);
  },
  M14: (model) => {
    const site = findSite(model, `candidate/skills/${PLANS[0]}/${EXPORT}`);
    site.meta.log_after = { lines: 4, sha256: sha256("M14 cross lane log drift") };
  },
  M15: (model) => {
    genericRefusal(findSite(model, `candidate/skills/${PLANS[0]}/${EXPORT}`), "evidence_incomplete", "M15 mixed pair");
  },
  M16: (model) => {
    for (const plan of PLANS) {
      for (const lane of ["reference", "candidate"]) {
        genericRefusal(findSite(model, `${lane}/ai-catapult/${plan}/${AUDIT}`), "audit_refused", "M16 generic audits");
      }
    }
  },
  M17: (model) => {
    model.normalizations = [{ class: "unknown-class", site: "/refusals/0/detail" }];
  },
  M18: (model) => {
    const site = findSite(model, `candidate/skills/${PLANS[0]}/${AUDIT}`);
    rewriteStdout(site, (text) => {
      const line = lineOf(text, '"provenance"');
      return `${text.slice(0, line.end)}  "provenance": "base-copy",\n${text.slice(line.end)}`;
    });
  },
  M19: (model) => {
    const site = withWorld(model, findSite(model, `candidate/skills/${PLANS[0]}/${AUDIT}`));
    reRender(site, { target_revision: "0".repeat(40) });
    replace(model, site);
  },
  M20: (model) => {
    const site = findSite(model, `candidate/skills/${PLANS[0]}/${AUDIT}`);
    site.stdout = Buffer.from("[1, 2, 3]\n", "utf8");
  },
  M21: (model) => {
    const site = withWorld(model, findSite(model, `candidate/skills/${PLANS[0]}/${AUDIT}`));
    reRender(site, { findings: [{ code: "synthetic_finding", severity: "info" }] });
    replace(model, site);
  },
  M22: (model) => {
    model.lanes.reference.common_dir = "/nonexistent/synthetic/reference-common-dir";
  },
  M23: (model) => {
    model.lanes.candidate.driver_commit = model.lanes.reference.driver_commit;
  },
  M24: (model) => {
    const site = findSite(model, `candidate/skills/${PLANS[0]}/${AUDIT}`);
    rewriteStdout(site, (text) => {
      const line = lineOf(text, '"findings"');
      return `${text.slice(0, line.start)}  "findings": [\n      {"nested": {"provenance": "base-copy"}}\n  ],\n${text.slice(line.end)}`;
    });
  },
  M25: (model) => {
    model.normalizations = [{ class: "scratch-path", site: "/refusals/0/detail" }];
  },
  M26: (model) => {
    model.normalizations = [{ class: "interpreter-diagnostic", site: "stderr" }];
  },
  M27: (model) => {
    model.lanes.targets = model.lanes.targets.filter((target) => target.repository !== "ai-factory");
    model.sites = model.sites.filter((site) => site.repository !== "ai-factory");
    delete model.registries["ai-factory"];
    delete model.policies["ai-factory"];
  },
  M28: (model) => {
    const site = withWorld(model, findSite(model, `candidate/skills/${PLANS[0]}/${EXPORT}`));
    reRender(site, { exported_at: undefined, log_sha256: undefined, schema: "merge-audit/1", findings: [], merged_at: "2026-10-19T12:00:05Z", target_revision: model.lanes.targets[0].revision });
    replace(model, site);
  },
  M29: (model) => {
    const site = withWorld(model, findSite(model, `candidate/skills/${PLANS[0]}/${AUDIT}`));
    reRender(site, { plan_id: "other-plan" });
    replace(model, site);
  },
  M30: (model) => {
    const site = findSite(model, `candidate/skills/${PLANS[0]}/${AUDIT}`);
    const argv = site.meta.argv.slice();
    argv[argv.length - 1] = "other-plan";
    site.meta.argv = argv;
  },
  M31: (model) => {
    const site = findSite(model, `candidate/skills/${PLANS[0]}/${EXPORT}`);
    site.meta.log_before = { lines: 2, sha256: sha256("M31 before log drift") };
  },
  M32: (model) => {
    const site = findSite(model, `candidate/skills/${PLANS[0]}/${AUDIT}`);
    site.meta.started_at = "2026-01-01T00:00:00Z";
    site.meta.finished_at = "2026-01-01T00:00:05Z";
  },
  M33: (model) => {
    const site = findSite(model, `candidate/ai-factory/${PLANS[0]}/${EXPORT}`);
    const path = "evidence/log.mdl";
    const bytes = Buffer.from("M33 refusal written drift\n", "utf8");
    site.files.after[path] = bytes;
    site.meta.written[path] = sha256(bytes);
  },
  M34: (model) => {
    const site = findSite(model, `candidate/skills/${PLANS[0]}/${AUDIT}`);
    rewriteStdout(site, (text) => {
      const line = lineOf(text, '"provenance"');
      return `${text.slice(0, line.start)}  "provenance": "source-lane", "extra": true,\n${text.slice(line.end)}`;
    });
  },
  O03: (model) => {
    model.lanes.targets[0].common_dir = "/nonexistent/synthetic/false-common-dir";
    model.lanes.candidate.driver_commit = "f".repeat(40);
  },
  O08: (model) => {
    for (const repository of REPOS) {
      for (const plan of PLANS) {
        for (const lane of ["reference", "candidate"]) {
          genericRefusal(findSite(model, `${lane}/${repository}/${plan}/${AUDIT}`), "audit_refused", "O08 generic audits");
        }
      }
    }
  },
  R01: (model) => {
    for (const [index, lane] of ["reference", "candidate"].entries()) {
      const site = findSite(model, `${lane}/skills/${PLANS[0]}/${AUDIT}`);
      const offset = site.stdout.indexOf("2026-");
      site.stdout[offset] = 0x80 + index;
    }
  },
  R02: (model) => {
    const site = findSite(model, `candidate/skills/${PLANS[0]}/${AUDIT}`);
    rewriteStdout(site, (text) => text.replace('"provenance": ', '"\\u0070rovenance"\t :\t'));
  },
  R03: (model) => {
    for (const lane of ["reference", "candidate"]) rewriteStdout(findSite(model, `${lane}/skills/${PLANS[0]}/${AUDIT}`), (text) => text.replace('  "target_revision"', '  "schema": "unknown-schema",\n  "target_revision"'));
  },
  R04: (model) => {
    for (const lane of ["reference", "candidate"]) rewriteStdout(findSite(model, `${lane}/skills/${PLANS[0]}/${AUDIT}`), (text) => text.replace('  "findings": [],', '  "findings": [],\n  "findings": [],'));
  },
  R05: (model) => {
    for (const lane of ["reference", "candidate"]) rewriteStdout(findSite(model, `${lane}/ai-factory/${PLANS[0]}/${EXPORT}`), (text) => text.replace('{\n', '{\n  "invalid": NaN,\n'));
  },
  R06: (model) => { findSite(model, `candidate/ai-factory/${PLANS[0]}/${EXPORT}`).files.after["evidence/hidden.txt"] = Buffer.from("unmapped drift\n"); },
  R07: (model) => {
    for (const site of model.sites.filter((s) => s.operation === EXPORT && s.meta.exit === 0)) {
      site.files = { before: {}, after: {} }; site.meta.written = {}; site.meta.written_before = {};
    }
  },
  R08: (model) => { for (const site of model.sites.filter((s) => s.operation === EXPORT)) { site.meta.written = {}; site.meta.written_before = {}; } },
  R09: (model) => {
    model.lanes.targets[0].root = "/nonexistent/synthetic/target";
    for (const site of model.sites.filter((s) => s.repository === "skills")) site.meta.argv[4] = model.lanes.targets[0].root;
  },
  R10: (model) => {
    // Commit objects and cwd are unchanged; only the requested fully-qualified
    // ref differs. Re-record real Git responses, not an injected pass flag.
    model.lanes.targets[0].ref = "refs/heads/main";
  },
  R11: (model) => { model.observation.lanes_sha256 = "0".repeat(64); },
  R12: (model) => { model.observation.commands[0].cwd = "/nonexistent/synthetic/cwd"; },
  R13: (model) => { model.observation.commands[0].stderr = Buffer.from("not the observed stderr\n").toString("base64"); },
  R14: (model) => { for (const site of model.sites) { site.meta.started_at = "invalid"; site.meta.finished_at = "invalid"; } },
  R15: (model) => {
    for (const lane of ["reference", "candidate"]) rewriteStdout(findSite(model, `${lane}/skills/${PLANS[0]}/${AUDIT}`), (text) => text.replace('{\n', '{\n  "generation": "wrong-generation",\n'));
  },
  R16: (model) => { for (const site of model.sites.filter((s) => s.operation === EXPORT && s.repository === "ai-factory")) { site.meta.exit = 0; site.exit = 0; } },
  R17: (model) => { delete findSite(model, `candidate/ai-factory/${PLANS[0]}/${EXPORT}`).files.after["evidence/log.mdl"]; },
  R18: (model) => { for (const site of model.sites.filter((s) => s.operation === EXPORT)) { site.meta.log_before = "invalid"; site.meta.log_after = "invalid"; } },
  R19: (model) => { model.observation.commands[0].stdout += "!"; },
  R20: (model) => {
    for (const lane of ["reference", "candidate"]) rewriteStdout(findSite(model, `${lane}/skills/${PLANS[0]}/${AUDIT}`), (text) => text.replace('"merged_at": "', '"merged_at": "é🧭'));
  },
  R22: (model) => { model.extraMetadata = true; },
  R23: (model) => {
    model.lanes.candidate.driver_root = "/nonexistent/synthetic/candidate";
    for (const site of model.sites.filter((s) => s.lane === "candidate")) site.meta.cwd = model.lanes.candidate.driver_root;
  },
  R24: (model) => { findSite(model, `candidate/skills/${PLANS[0]}/${EXPORT}`).meta.written["evidence/log.mdl"] = "invalid-digest"; },
  R25: (model) => { findSite(model, `candidate/skills/${PLANS[0]}/${AUDIT}`).meta.log_before = { sha256: null, lines: 0 }; },
  R26: (model) => { Object.defineProperty(findSite(model, `candidate/ai-factory/${PLANS[0]}/${EXPORT}`).files.after, "__proto__", { value: Buffer.from("unmapped reserved-name snapshot\n"), enumerable: true }); },
  R27: (model) => {
    model.lanes.targets[0].target = "other"; model.lanes.targets[0].ref = "main";
    for (const site of model.sites.filter((s) => s.repository === "skills")) site.meta.argv[6] = "other";
  },
};

function replace(model, site) {
  const index = model.sites.findIndex((entry) => siteKey(entry) === siteKey(site));
  model.sites[index] = site;
}

function resequence(model) {
  const ordered = [...model.sites].sort((left, right) => (left.meta.started_at < right.meta.started_at ? -1 : 1));
  ordered.forEach((site, index) => {
    site.meta.sequence = index + 1;
  });
  model.sites = ordered;
}

function genericRefusal(site, code, detail) {
  site.stdout = Buffer.from(pretty({ code, detail, schema: "readiness-contract/2" }), "utf8");
  site.exit = 2;
  site.meta.exit = 2;
}

export function applyMutations(model, mutations) {
  for (const mutation of mutations) {
    const apply = MUTATIONS[mutation];
    if (apply === undefined) {
      throw new Error(`unknown fixture mutation ${mutation}`);
    }
    apply(model);
  }
  return model;
}

export function renormalize(model) {
  model.observation.lanes_sha256 = sha256(Buffer.from(`${JSON.stringify(sortDeep(model.lanes))}\n`, "utf8"));
  return model;
}

function sortDeep(value) {
  if (Array.isArray(value)) {
    return value.map(sortDeep);
  }
  if (value !== null && typeof value === "object") {
    const out = {};
    for (const key of Object.keys(value).sort()) {
      out[key] = sortDeep(value[key]);
    }
    return out;
  }
  return value;
}

export { REFUSAL_CODES, REPOS };
