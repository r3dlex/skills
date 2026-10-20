import { spawnSync } from "node:child_process";
import { mkdirSync, realpathSync, writeFileSync } from "node:fs";
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
const CHOICE_QUOTING_PROBE = [
    "import argparse, contextlib, io, sys",
    "parser = argparse.ArgumentParser(add_help=False)",
    "parser.add_argument('--kind', choices=['output', 'trajectory'])",
    "rendered = io.StringIO()",
    "try:",
    "    with contextlib.redirect_stderr(rendered):",
    "        parser.parse_args(['--kind', 'bogus'])",
    "except SystemExit:",
    "    pass",
    "sys.stdout.write('quoted' if \"'output'\" in rendered.getvalue() else 'bare')",
].join("\n");
let choicesAreQuoted;
export function main(argv) {
    let skill;
    let root = ".";
    let kind = "output";
    const takesValue = new Set(["--skill", "--root", "--kind"]);
    let skip = false;
    for (const flag of argv) {
        if (skip) {
            skip = false;
            continue;
        }
        if (takesValue.has(flag)) {
            skip = true;
            continue;
        }
        if (flag === "-h" || flag === "--help") {
            const probed = spawnSync("python3", ["-c", "import sys; print(0 if sys.version_info >= (3, 10) else 1)"], { encoding: "utf8" });
            const heading = probed.stdout.trim() === "0" ? "options:" : "optional arguments:";
            process.stdout.write(`usage: scaffold-eval.py [-h] --skill SKILL [--root ROOT]\n                        [--kind {output,trajectory}]\n\nScaffold a structurally valid eval triplet for a target skill, offline. Given\na target skill name, write the P0 eval shape under\n\`\`<root>/.ai/evals/<skill>/\`\`: - \`\`evalset.json\`\` labelled cases\n(schema_version, set_id, kind, cases) - \`\`rubric.md\`\` scoring rubric\n(criteria, weights summing to 1.0, threshold) - \`\`judge-config.json\`\` LM-judge\nharness stub (tier/mode/harness/evaluates, \`\`execution: out-of-band\`\`) No\nmodel or network call is made. The judge declared in \`\`judge-config.json\`\` is\nan out-of-band stub: this script never invokes it, and CI never invokes it.\nSee \`\`eval-a-skill/SKILL.md\`\` and \`\`ai-catapult-init/modules/evals.md\`\`.\nUsage: scaffold-eval.py --skill <name> [--root <dir>] [--kind\noutput|trajectory] Idempotent: re-running rewrites the triplet in place; no\nduplicate files.\n\n${heading}\n  -h, --help            show this help message and exit\n  --skill SKILL         target skill name\n  --root ROOT           repo root to write under\n  --kind {output,trajectory}\n                        evalset kind (default: output)\n`);
            return 0;
        }
    }
    const unknown = [];
    for (let index = 0; index < argv.length; index += 1) {
        const token = argv[index] ?? "";
        const eq = token.indexOf("=");
        const inline = token.startsWith("--") && eq > 2 ? token.slice(eq + 1) : undefined;
        const flag = inline === undefined ? token : token.slice(0, eq);
        if (!takesValue.has(flag)) {
            unknown.push(token);
            continue;
        }
        const next = argv[index + 1];
        const optionLike = next !== undefined && next.length > 1 && next.startsWith("-") && !/^-\d+(\.\d*)?$|^-\.\d+$/.test(next);
        const value = inline !== undefined ? inline : (next !== undefined && !optionLike ? next : undefined);
        if (value === undefined) {
            process.stderr.write(`usage: scaffold-eval.py [-h] --skill SKILL [--root ROOT]\n                        [--kind {output,trajectory}]\nscaffold-eval.py: error: argument ${flag}: expected one argument\n`);
            return 2;
        }
        if (flag === "--kind" && value !== "output" && value !== "trajectory") {
            // Argparse renders the choice list quoted or bare, and that switch
            // moved within a patch series too: 3.12.3 quotes, 3.12.15 does not.
            // Render it the way this interpreter renders it, memoised.
            if (choicesAreQuoted === undefined) {
                const probed = spawnSync("python3", ["-c", CHOICE_QUOTING_PROBE], { encoding: "utf8" });
                // A probe that cannot run, or that answers with anything other
                // than a recognised "bare" verdict, keeps the quoted form this
                // port emitted before the probe existed.
                choicesAreQuoted = probed.status !== 0 || probed.stdout.trim() !== "bare";
            }
            const choices = choicesAreQuoted ? "'output', 'trajectory'" : "output, trajectory";
            process.stderr.write(`usage: scaffold-eval.py [-h] --skill SKILL [--root ROOT]\n                        [--kind {output,trajectory}]\nscaffold-eval.py: error: argument --kind: invalid choice: '${value}' (choose from ${choices})\n`);
            return 2;
        }
        if (flag === "--skill") {
            skill = value;
        }
        else if (flag === "--root") {
            root = value;
        }
        else if (flag === "--kind") {
            kind = value;
        }
        if (inline === undefined) {
            index += 1;
        }
    }
    if (skill === undefined) {
        process.stderr.write("usage: scaffold-eval.py [-h] --skill SKILL [--root ROOT]\n                        [--kind {output,trajectory}]\nscaffold-eval.py: error: the following arguments are required: --skill\n");
        return 2;
    }
    if (unknown.length > 0) {
        process.stderr.write(`usage: scaffold-eval.py [-h] --skill SKILL [--root ROOT]\n                        [--kind {output,trajectory}]\nscaffold-eval.py: error: unrecognized arguments: ${unknown.join(" ")}\n`);
        return 2;
    }
    const out = scaffold(skill, resolve(root), kind);
    process.stdout.write(`scaffolded eval triplet: ${realpathSync(out)}\n`);
    return 0;
}
if (invokedDirectly(import.meta.url)) {
    process.exit(main(process.argv.slice(2)));
}
//# sourceMappingURL=scaffold-eval.mjs.map