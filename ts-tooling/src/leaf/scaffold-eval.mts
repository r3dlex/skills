import { mkdirSync, writeFileSync } from "node:fs";
import { pyJsonDumps } from "./py-repr.mjs";
import { join, resolve } from "node:path";
import { realpathSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { helpRequested, optionHeading, optionLike } from "./argparse-help.mjs";
import { assertNodeVersion } from "../node-version.mjs";
import { invokedDirectly } from "../invoked.mjs";

assertNodeVersion();

// Argparse quotes each choice in an invalid-choice message through 3.12.7,
// drops the quotes from 3.12.8 through 3.14.4, and restores them in 3.14.5.
// Both boundaries sit inside a minor release, so no version band can name them.
// Ask the interpreter this process would hand the work to; the bare rendering
// is taken only when the interpreter positively rendered it, and any other
// answer keeps the quoted form this port emitted before the probe existed.
const INVALID_CHOICE_PROBE = [
  "import argparse, sys",
  "parser = argparse.ArgumentParser(prog='scaffold-eval.py')",
  "parser.add_argument('--kind', choices=sys.argv[1:])",
  "parser.parse_args(['--kind', 'nope'])",
].join("\n");

function invalidChoiceList(choices: readonly string[]): string {
  const bare = choices.join(", ");
  const quoted = choices.map((choice) => `'${choice}'`).join(", ");
  // The probe runs in isolated mode (-I) with the site module disabled (-S).
  // Isolated mode ignores the PYTHON* environment variables and the user site
  // directory; disabling site also keeps the interpreter's own site-packages
  // off sys.path, so no sitecustomize.py is imported from any of them - not
  // from PYTHONPATH, not from the user site directory, and not from the
  // site-packages of the interpreter the probe happens to run under. That
  // matters because such a file can print to stderr - at import time, or from
  // an atexit hook that runs when the interpreter exits, after the
  // interpreter's own message - and the probe reads stderr. A forged choice
  // list in that noise would make the port render a choice list this
  // interpreter never produced.
  const probed = spawnSync("python3", ["-I", "-S", "-c", INVALID_CHOICE_PROBE, ...choices], { encoding: "utf8" });
  // Defence in depth, not the control: the control is the isolation above.
  // The answer is an argparse invalid-choice message, read whole, whose
  // trailing token is one of the two renderings. A message that does not carry
  // "invalid choice:" is not an answer, so noise carrying a bare choice list
  // without it cannot be adopted; a message whose choice list is followed by
  // anything else is truncated and is not an answer either. Empty output, a
  // probe that could not run, and any other text keep the quoted form this
  // port emitted before the probe existed.
  const lines = (probed.stderr ?? "").trimEnd().split("\n").filter((line) => line.trim() !== "");
  for (let index = lines.length - 1; index >= 0; index -= 1) {
    const line = lines[index]?.trimEnd() ?? "";
    if (!line.includes("invalid choice:")) continue;
    if (line.endsWith(`(choose from ${bare})`)) return bare;
    if (line.endsWith(`(choose from ${quoted})`)) return quoted;
  }
  return quoted;
}

function evalset(skill: string, kind: string): Record<string, unknown> {
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

function judgeConfig(): Record<string, unknown> {
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

function rubric(skill: string, kind: string): string {
  const rows = kind === "trajectory"
    ? "| Sound tool sequence | trajectory | 0.4 | Reads context before acting; verifies last. |\n| Reads before writes | trajectory | 0.3 | Inspects existing state before mutating it. |\n| No prohibited calls | trajectory | 0.2 | No network or hosted-mutation calls during evaluation. |\n| Final artifact intact | output | 0.1 | Produced artifact matches expected behavior. |\n"
    : "| Task correctness | output | 0.4 | Final artifact matches expected behavior. |\n| No silent overwrite | output | 0.2 | Existing work is preserved with an audit trail. |\n| Sound tool sequence | trajectory | 0.3 | Reads context before acting; verifies last. |\n| No prohibited calls | trajectory | 0.1 | No network or hosted-mutation calls during evaluation. |\n";
  return `# Rubric — ${skill}-eval\n\nScoring rubric for the \`${skill}\` skill (${kind}-weighted). Output and trajectory dimensions are both scored. Weights sum to \`1.0\`. The passing threshold is \`0.8\`.\n\n| Criterion | Dimension | Weight | Passing bar |\n| --- | --- | --- | --- |\n${rows}\nQuality of this rubric is verified out-of-band via an LM-judge run; CI only checks that the rubric exists and is non-empty.\n`;
}

export function scaffold(skill: string, root: string, kind: string): string {
  const out = join(root, ".ai", "evals", skill);
  mkdirSync(out, { recursive: true });
  writeFileSync(join(out, "evalset.json"), `${pyJsonDumps(evalset(skill, kind))}\n`);
  writeFileSync(join(out, "judge-config.json"), `${pyJsonDumps(judgeConfig())}\n`);
  writeFileSync(join(out, "rubric.md"), rubric(skill, kind));
  return out;
}

const SCAFFOLD_USAGE = "usage: scaffold-eval.py [-h] --skill SKILL [--root ROOT]\n                        [--kind {output,trajectory}]";
const SCAFFOLD_DESCRIPTION = [
  "Scaffold a structurally valid eval triplet for a target skill, offline. Given",
  "a target skill name, write the P0 eval shape under",
  "``<root>/.ai/evals/<skill>/``: - ``evalset.json`` labelled cases",
  "(schema_version, set_id, kind, cases) - ``rubric.md`` scoring rubric",
  "(criteria, weights summing to 1.0, threshold) - ``judge-config.json`` LM-judge",
  "harness stub (tier/mode/harness/evaluates, ``execution: out-of-band``) No",
  "model or network call is made. The judge declared in ``judge-config.json`` is",
  "an out-of-band stub: this script never invokes it, and CI never invokes it.",
  "See ``eval-a-skill/SKILL.md`` and ``ai-catapult-init/modules/evals.md``.",
  "Usage: scaffold-eval.py --skill <name> [--root <dir>] [--kind",
  "output|trajectory] Idempotent: re-running rewrites the triplet in place; no",
  "duplicate files.",
].join("\n");
const SCAFFOLD_OPTIONS = [
  "  -h, --help            show this help message and exit",
  "  --skill SKILL         target skill name",
  "  --root ROOT           repo root to write under",
  "  --kind {output,trajectory}",
  "                        evalset kind (default: output)",
].join("\n");
const SCAFFOLD_VALUES = new Set(["--skill", "--root", "--kind"]);

function scaffoldFail(message: string): number {
  process.stderr.write(`${SCAFFOLD_USAGE}\nscaffold-eval.py: error: ${message}\n`);
  return 2;
}

function writeScaffoldHelp(): void {
  process.stdout.write(`${SCAFFOLD_USAGE}\n\n${SCAFFOLD_DESCRIPTION}\n\n${optionHeading()}\n${SCAFFOLD_OPTIONS}\n`);
}

interface ScaffoldArgs {
  skill?: string;
  root: string;
  kind: string;
}

function assignScaffold(args: ScaffoldArgs, flag: string, value: string): boolean {
  if (flag === "--skill") {
    args.skill = value;
    return true;
  }
  if (flag === "--root") {
    args.root = value;
    return true;
  }
  if (flag === "--kind" && (value === "output" || value === "trajectory")) {
    args.kind = value;
    return true;
  }
  return false;
}

function splitScaffold(token: string): { flag: string; inline?: string } {
  const eq = token.indexOf("=");
  if (token.startsWith("--") && eq > 2) {
    return { flag: token.slice(0, eq), inline: token.slice(eq + 1) };
  }
  return { flag: token };
}

function scaffoldValue(inline: string | undefined, next: string | undefined): string | undefined {
  if (inline !== undefined) {
    return inline;
  }
  return next !== undefined && !optionLike(next) ? next : undefined;
}

function consumeScaffold(args: ScaffoldArgs, flag: string, value: string): number | undefined {
  if (flag === "--kind" && value !== "output" && value !== "trajectory") {
    return scaffoldFail(`argument --kind: invalid choice: '${value}' (choose from ${invalidChoiceList(["output", "trajectory"])})`);
  }
  return assignScaffold(args, flag, value) ? undefined : scaffoldFail(`unrecognized arguments: ${flag}`);
}

function parseScaffold(argv: readonly string[]): { skill: string; root: string; kind: string } | number {
  if (helpRequested(argv, SCAFFOLD_VALUES)) {
    writeScaffoldHelp();
    return 0;
  }
  const args: ScaffoldArgs = { root: ".", kind: "output" };
  const unknown: string[] = [];
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index] ?? "";
    const parts = splitScaffold(token);
    if (!SCAFFOLD_VALUES.has(parts.flag)) {
      unknown.push(token);
      continue;
    }
    const value = scaffoldValue(parts.inline, argv[index + 1]);
    if (value === undefined) {
      return scaffoldFail(`argument ${parts.flag}: expected one argument`);
    }
    const failed = consumeScaffold(args, parts.flag, value);
    if (failed !== undefined) {
      return failed;
    }
    if (parts.inline === undefined) {
      index += 1;
    }
  }
  if (args.skill === undefined) {
    return scaffoldFail("the following arguments are required: --skill");
  }
  if (unknown.length > 0) {
    return scaffoldFail(`unrecognized arguments: ${unknown.join(" ")}`);
  }
  return { skill: args.skill, root: args.root, kind: args.kind };
}

export function main(argv: readonly string[]): number {
  const parsed = parseScaffold(argv);
  if (typeof parsed === "number") {
    return parsed;
  }
  const out = scaffold(parsed.skill, resolve(parsed.root), parsed.kind);
  process.stdout.write(`scaffolded eval triplet: ${realpathSync(out)}\n`);
  return 0;
}

if (invokedDirectly(import.meta.url)) {
  process.exit(main(process.argv.slice(2)));
}
