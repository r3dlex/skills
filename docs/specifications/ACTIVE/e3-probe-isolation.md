# E3: scaffold-eval choice-list probe isolation (skills, plan `e3`, goal `probe-isolation`)

> `readiness-contract/2` planning publication, live mode. This plan registers **one goal,
> `probe-isolation`**. It is a **defect-fix successor** to the merged goal `e6-sk-01-py-leaf`: the
> scaffold-eval port asks the interpreter how argparse renders an invalid-choice list, reads the
> answer off **stderr**, and interpreter startup noise lands on stderr too — so a forged choice list
> could make the port render something the interpreter never produced.
>
> Publication grants no authority. No plan approval is minted by this publication. No implementation is
> dispatched by it.

## 1. The defect

The port probes the interpreter with `spawnSync("python3", [...])` and reads the invalid-choice message
off the interpreter's **stderr**. Anything the interpreter's startup prints — a `sitecustomize.py`
reached through `PYTHONPATH` or the user site directory, at import time or from an `atexit` hook that
runs after the interpreter's own message — arrives on the same stderr. A forged choice list in that
noise makes the port render a choice list the interpreter never produced.

Two vectors are closed by the isolation:

* `PYTHONPATH` and the user site directory are ignored under `-I`;
* the interpreter's **own `site-packages`** is **not** excluded by `-I` alone — with the `site` module
  disabled under `-S`, `site-packages` never reaches `sys.path`, so no `sitecustomize.py` can be
  imported from it at all.

## 2. The two copies

| copy | path | provenance |
|---|---|---|
| canonical | `scripts/lib/leaf/scaffold-eval.mjs` | compiled from `ts-tooling/src/leaf/scaffold-eval.mts` by the repository's own `ts-build-drift` recipe |
| packaged public | `04-validate-handoff/eval-a-skill/lib/scaffold-eval.mjs` | a **hand-maintained sibling-flat projection** |

The packaged copy is proven to be hand-maintained: its only in-tree references are
`04-validate-handoff/eval-a-skill/scaffold-eval.py:14` (`ENTRY_REL`), the legacy-freeze baseline row,
and runtime invocations in `tests/e6_py_leaf_parity_test.sh`; **no build or install rule emits it**;
the `ts-build-drift` hook compares `scripts/lib` only; and its bytes differ structurally from what the
canonical source compiles to (it vendors `pyJsonDumps` inline, imports `./node-version.mjs` and
`./invoked.mjs` where the canonical copy imports `../node-version.mjs`, and imports neither
`py-repr.mjs` nor `argparse-help.mjs` (as import specifiers)).

**Its `.mjs.map` is therefore left byte-unchanged**, and its status recorded rather than left implicit:
the map still claims `sources: ["../../../ts-tooling/src/leaf/scaffold-eval.mts"]`, a path that resolves
correctly, so **the map reads as if the packaged copy were a build product — and it is not.** Deleting
it would change the package shape and must be checked against the catalog and the install-parity tests
first; inventing a build step is larger than the defect. A mandatory **structural drift guard** (AC-14)
is what makes a reader's mistaken belief false rather than merely unlikely.

**The dual-path translation is manual and is submitted for express review.** It is two edits: the same
isolation flags on the packaged copy's choice-list probe, and the same whole-message read rule. Nothing
else in the packaged copy changes — no import, no help text, no argument parsing, no output byte, no exit
code.

## 3. Scope

```
ts-tooling/src/leaf/scaffold-eval.mts
scripts/lib/leaf/scaffold-eval.mjs
scripts/lib/leaf/scaffold-eval.mjs.map
04-validate-handoff/eval-a-skill/lib/scaffold-eval.mjs
04-validate-handoff/eval-a-skill/lib/scaffold-eval.mjs.map
tests/e6_scaffold_eval_probe_test.sh
.ai/evidence/probe-isolation.json
```
**The seventh path is the goal's TDD evidence file**, and it is in the **reviewed write scope** — not merely mentioned in
an attachment. It is the literal path the goal's red-then-green evidence is recorded at, so the write must be inside the
scope that the plan approval covers.

**Not in scope, and named so it cannot be lost:** `tests/e6_py_leaf_parity_test.sh` (sha256-pinned),
`.ai/ci/local-ci.json`, `.ai/rules/legacy-freeze-baseline.json`, the D13 generation-1 seven literal paths,
and `04-validate-handoff/autobahn/**`.

**No re-pin and no baseline edit is proposed** — and this is a **recommendation, not an accepted
exclusion**. Review must explicitly justify exclusion, select a separately reviewed pinning slice, or admit the scope
extension to `.ai/ci/local-ci.json` before changing it. **Complete declared local CI remains required in every case**;
no silent re-pin or scope expansion. **On the legacy-freeze baseline the obligation is OPEN**: the new test is absent
from the baseline and it contains Python fixture bodies and interpreter `-c` programs, and the scanner's
`embedsPython` helper matches the LITERAL token `python3` while the new test's probe uses a **variable** interpreter —
so a scanner's inability to recognise that interpreter is **not a semantic exemption**, and the obligation must be
decided against the actual final test design. **No hook failure is claimed without execution.** If a baseline, policy
or scope change proves necessary it requires **its own admission**, not a growth entry added to silence the gate. ADR-0015: *"Supporting sources include direct script entrypoints and reviewed indirect inputs …
Hashes establish freshness, not authenticity or semantic completeness; repository review owns whether
local checks are sufficient. The manifest does not statically trace all script imports."* The
`sources` map is a reviewed subset — 36 of 118 `tests/*.sh` are pinned and 82 are not — so the exclusion
of this goal's paths is **PROPOSED, and remains a REVIEW-OWNED DECISION THAT HAS NOT BEEN MADE**. A decision to pin
them would extend the scope and need its own admission; a decision to exclude them must be justified explicitly by
repository review. **No exclusion is recorded as completed, and none is assumed here.**

## 4. Acceptance criteria

The goal's **sixteen** acceptance criteria are carried in the published bundle's goal object, and are the
operative text. In outline:

* **AC-1 / AC-2** — the choice-list probe is isolated with `-I -S` on the canonical copy and on the
  packaged copy, the latter verified **through the live public Python shim**; measured, not asserted.
* **AC-3 / AC-4** — compiled-vs-packaged parity, byte-identical; and **unchanged public behaviour** —
  the change alters only *which* interpreter output the port is willing to believe, never what it emits.
* **AC-5 / AC-6 / AC-7 / AC-8** — the read rule and the rendering are observable; the six killed mutants
  and the one survivor are enumerated with the property each pins; **no claim of complete mutation
  coverage is made**; the no-interpreter control resolves no `python3` before asserting the fallback; the
  PR #151 controls are live; an empty interpreter inventory is a failure, not a skip.
* **AC-9** — the packaged source map's disposition is recorded.
* **AC-10** — TDD evidence with the **same command** on both legs, where the red leg exercises the
  **packaged public entrypoint** and fails on it separately, because the packaged copy's defect is
  independent of the canonical copy's.
* **AC-11 / AC-12** — green at head, with the mutating parity harness run in a **disposable worktree**;
  no build drift.
* **AC-13** — the `PYTHON*` environment and `PYTHONHOME` cannot change what the probe measures, and this
  criterion is satisfied by **EITHER** of the two qualified prospective oracle forms and by no other: **FORM 1**
  actual-spawn observation of the choice-list child's argv and effective interpreter flags, **OR FORM 2** a
  qualified structural guard binding the absolute required flags at both live shipping sites. The standalone
  interpreter mechanism control is **not** a substitute for either, and **mutant B survives** until the criterion is
  written and observed.
* **AC-14** — the **absolute two-site isolation invariant** at the two **live shipping** choice-list spawns
  (`scripts/lib/leaf/scaffold-eval.mjs:25` **at the published base, relocated to `:36` by the repair**, and
  `04-validate-handoff/eval-a-skill/lib/scaffold-eval.mjs:105`, the latter reached through the live public Python shim),
  **each site identified by its call and its probe program rather than by a line number alone**, each spawning with
  **absolute `-I` AND `-S`**, with equivalent required read rules, and with the demonstration that **dropping `-I`
  independently at either required shipping site is detected** and that **both site bindings are demonstrated**. This is
  not "structural equivalence": two copies can agree while both omit `-I`.
* **AC-15** — interpreter **authenticity**: every interpreter the suite measures is asserted to be a genuine CPython
  binary — a Mach-O image (`cf fa ed fe`, `fe ed fa cf`, **or the universal `ca fe ba be`**), an ELF image
  (`7f 45 4c 46`) or a Windows PE image (`4d 5a`), **never a `#!` script** — and to report
  `sys.implementation.name == "cpython"`, so a substituted interpreter **fails the suite by name** instead of agreeing with
  the port on a forged rendering. This asserts the **shape and identity** of the executed file, **not its provenance**.
* **AC-16** — interpreter **stability**: each interpreter's resolved realpath is recorded before execution and
  re-resolved after, and a changed realpath or digest is a **failure, not a skip**; the measurement is valid only
  within its recorded observation window.

## 5. The residual, and its successor

Both copies also contain a **version probe** — `04-validate-handoff/eval-a-skill/lib/scaffold-eval.mjs:73`
and, on the canonical side, `ts-tooling/src/leaf/argparse-help.mts:5` (compiled to `scripts/lib/leaf/argparse-help.mjs`; there is no `argparse-help.mjs` source file, and the five canonical leaves import it through the build-compatible `./argparse-help.mjs` specifier) — which is likewise un-isolated and
can be moved by the same noise class. It is **left un-isolated in both copies**, which keeps
compiled-vs-packaged parity exact and keeps this goal surgical. The same defect family also lives in
`ts-tooling/src/leaf/catalog-query.mts:130,248,301`; the in-repo precedent is
`ts-tooling/src/leaf/validate-cascade-fixtures.mts:39`, which already uses `-I`.

**The sweep is NOT registered and is NOT a goal of this plan.** There is no successor goal id, no generation, no owner
and no handoff for it, and it has no registry entry. It is named here so it cannot be lost, and it becomes a separately
reviewed successor only when that successor is actually published and registered. **Its writes are not absorbed into
E3.** This one-goal packet does not close or register the sweep or the full defect family. The canonical version probe
lives in `ts-tooling/src/leaf/argparse-help.mts` (compiled to `scripts/lib/leaf/argparse-help.mjs`; there is no `argparse-help.mjs` source file, and the five canonical leaves import it through the build-compatible `./argparse-help.mjs` specifier), which **five** canonical leaves import — `catalog-query.mts:5`,
`check-markdown-links.mts:3`, `check-root-discovery.mts:3`, `generate-skill-docs.mts:3` and `scaffold-eval.mts:6` — which
is why the sweep is wider than a single file and why it is not absorbed here.

## 6. Gates

Every gate of the repository's own autobahn contract applies unchanged: TDD evidence; lint; **local CI
green as well as hosted CI green at the exact head**; the goal's `verification[]`; an independent
non-author review pair bound to the exact head with every comment resolved; a fresh exact-subject
merge-stage admission through `run-gates.sh --phase pre-merge`; live ordinary host authority; and cascade
closure of the goal's issue. **No admin, no bypass, no self-approval, no branch-policy change.**

## 7. Branch

The goal branch is **`fix/e3-probe-isolation`**, unchanged. With plan id `e3` and goal id
`probe-isolation` the live `branch_pattern` `^(feat|fix|chore)/<plan_id>-<goal_id>$` fills to
`^(feat|fix|chore)/e3-probe-isolation$`, which matches the existing branch as it stands. The plan's
goal-branch namespace is verified collision-free against all sixteen active plans' bundles.
