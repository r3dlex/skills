import { mkdirSync, writeFileSync } from "node:fs";
function pyJsonDumps(value, indent = 2) {
    const body = JSON.stringify(value, null, indent) ?? "null";
    return body.replace(/[^\u0000-\u007e]/g, (ch) => `\\u${ch.charCodeAt(0).toString(16).padStart(4, "0")}`);
}
import { join, resolve } from "node:path";
import { assertNodeVersion } from "./node-version.mjs";
import { invokedDirectly } from "./invoked.mjs";
assertNodeVersion();
function evalset(skill, kind) {
    return {
        schema_version: "1.0",
        set_id: `${skill}-eval`,
        kind,
        skill_under_test: skill,
        cases: [{
                case_id: "case-001",
                input: `Exercise the primary behavior of the '${skill}' skill.`,
                expected_behavior: "Produces the documented artifact with no silent overwrite and a sound, auditable tool-call sequence.",
                trajectory: ["read-context", "plan", "act", "verify"],
            }],
    };
}
function judgeConfig() {
    return {
        schema_version: "1.0",
        judge: {
            tier: "frontier",
            mode: "lm-judge",
            harness: "stub",
            evaluates: ["output", "trajectory"],
            passing_threshold: 0.8,
            execution: "out-of-band",
        },
        trajectory_trace: {
            schema_version: "1.0",
            records: "tool-call sequence with arguments and outcomes",
            scored_against: "rubric.md trajectory criteria",
        },
    };
}
function rubric(skill, kind) {
    const rows = kind === "trajectory"
        ? "| Sound tool sequence | trajectory | 0.4 | Reads context before acting; verifies last. |\n| Reads before writes | trajectory | 0.3 | Inspects existing state before mutating it. |\n| No prohibited calls | trajectory | 0.2 | No network or hosted-mutation calls during evaluation. |\n| Final artifact intact | output | 0.1 | Produced artifact matches expected behavior. |\n"
        : "| Task correctness | output | 0.4 | Final artifact matches expected behavior. |\n| No silent overwrite | output | 0.2 | Existing work is preserved with an audit trail. |\n| Sound tool sequence | trajectory | 0.3 | Reads context before acting; verifies last. |\n| No prohibited calls | trajectory | 0.1 | No network or hosted-mutation calls during evaluation. |\n";
    return `# Rubric — ${skill}-eval\n\nScoring rubric for the \`${skill}\` skill (${kind}-weighted). Output and trajectory dimensions are both scored. Weights sum to \`1.0\`. The passing threshold is \`0.8\`.\n\n| Criterion | Dimension | Weight | Passing bar |\n| --- | --- | --- | --- |\n${rows}\nQuality of this rubric is verified out-of-band via an LM-judge run; CI only checks that the rubric exists and is non-empty.\n`;
}
export function scaffold(skill, root, kind) {
    const out = join(root, ".ai", "evals", skill);
    mkdirSync(out, { recursive: true });
    writeFileSync(join(out, "evalset.json"), `${pyJsonDumps(evalset(skill, kind))}\n`);
    writeFileSync(join(out, "judge-config.json"), `${pyJsonDumps(judgeConfig())}\n`);
    writeFileSync(join(out, "rubric.md"), rubric(skill, kind));
    return out;
}
export function main(argv) {
    let skill;
    let root = ".";
    let kind = "output";
    for (let index = 0; index < argv.length; index += 1) {
        const flag = argv[index];
        const value = argv[index + 1];
        if (flag === "--skill" && value !== undefined) {
            skill = value;
            index += 1;
        }
        else if (flag === "--root" && value !== undefined) {
            root = value;
            index += 1;
        }
        else if (flag === "--kind" && (value === "output" || value === "trajectory")) {
            kind = value;
            index += 1;
        }
        else {
            process.stderr.write("usage: scaffold-eval.py --skill <name> [--root <dir>] [--kind output|trajectory]\n");
            return 2;
        }
    }
    if (skill === undefined) {
        process.stderr.write("the following arguments are required: --skill\n");
        return 2;
    }
    const out = scaffold(skill, resolve(root), kind);
    process.stdout.write(`scaffolded eval triplet: ${out}\n`);
    return 0;
}
if (invokedDirectly(import.meta.url)) {
    process.exit(main(process.argv.slice(2)));
}
//# sourceMappingURL=scaffold-eval.mjs.map