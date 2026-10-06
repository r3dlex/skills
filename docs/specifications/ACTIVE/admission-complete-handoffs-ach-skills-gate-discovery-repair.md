# Gate discovery repair — publication candidate

Repository-owned LIVE plan `skills / ach-skills-gate-discovery-repair`, one future product goal `ACH-GW-DISC-01`. This specification defines the accepted discovery prerequisite, not an implementation, successful certificate or O8 receipt. The current Northstar continuation prepares **publication metadata only** for independent review.

## 1. Read and act by stage

1. **Publication reviewer:** compare the complete candidate against freshly observed main, the six preserved ACs/four product paths and the external D5 receipt below. Accept/reject these changed bytes separately from the original nine-input review; complete when both existing independent axes return exact-candidate verdicts.
2. **Publisher after review:** recheck the actual main-owned metadata slot, current policy/anchor/driver and complete-diff routing. The supported `02-govern-plan/northstar/handoff-write.sh` runs its own planning simulation before writing. Local emission and a planning-complete report grant no product authority; committing/pushing/PR finalization and ordinary publication merge remain later independent gates.
3. **Future product owner after publication:** obtain this generation's own approval, independently verify current authority, and pass clean exact-subject implementation admission before any source/test change. Complete only with actual red/green evidence, full CI, independent code/security review, signed review/certification and formal ordinary host authority.
4. **S-08 successor owner:** wait for the actual qualified discovery product merge and fresh receipt/ancestry before refreshing/publishing S-08 or reusing held WIP. Only the final fully governed S-08 successor merge may conditionally establish O8.

The generated `goals.json` is the sole home of all six product ACs, their exact four paths and `verification[]`. Those fields are byte-for-byte content-preserved from the reviewed discovery draft. Do not interpret publication paths as extra product scope.

## 2. Accepted decision and changed publication bindings

D5-20261006 **ACCEPTED the planning sequence**: discovery first, corrected S-08 later, original S-08 HELD/immutable/uncredited with claims preserved. External workspace receipt `.omc/handoffs/ach-20261004/D5-DECISION-20261006.json` has raw SHA256 `136279cf2742dc31c74a3d73301fce721052e81aabd0f7505f7f76b8f150d9d8`, accepted nine-input aggregate `58ac1d5d079195b72f8407e6eaaf926101c92751f052eac07cb4f470b2a7dea5`. The historical packet's null/pending fields and all reviewed bytes remain untouched.

That receipt authenticates the old reviewed inputs, **not this candidate's changed bundle/spec/sidecar or a future generation**. Candidate acceptance requires new independent review. D5 does not issue a plan approval, signature/tag, authority token, admitted stage, implementation window, host approval or merge waiver. The user's separate continuation assigns the retained publisher preparation work; main's actual exact-path slot and current producer validation remain independent requirements.

Current prepared base: `6b1e893238a64e8db933755ed1f954858c7c6eea`, observed through a normal fetch and matching `git ls-remote` in the owned worktree. LIVE policy raw SHA256 `58bcd9e7ba044479e2f9f64bedd147926e8ea706f9d9c51378294dada52b354a`, public anchor expected/actual SHA256 `8b33406c8f2cfe54c0a4204f63ffa03e5c1a35aa0b648d0d3a7a35399ecb14f1`; all nineteen producer/consumer pins match that immutable target. These dated facts must be rechecked at publication/review/merge; no trust anchor, driver or frozen helper is changed.

The prospective **new, unpublished** sidecar changes prior proposal-level `blocked` values to **`unknown`, never `ready`**, and retains unknown coverage plus legacy-safe TDD. Current producer refuses any `blocked` stage before planning simulation; unknown is its supported unready publication form. This is not registered-sidecar loosening or removal of runtime gates. Planning disposition/window evidence must exist before emission; future approval/admission, source sequencing, runtime proof and merge evidence are still missing. Missing evidence remains a real gap rather than a readiness assertion.

## 3. Immutable self-bootstrap proof

Source citations are skills objects at `6b1e893238a64e8db933755ed1f954858c7c6eea`. S-07 upstream release is `2ac9926fb007a1b98cdc6f7a77196767e62bf652`, currently an ancestor of main; it is not a certificate for this goal.

| Link | Decisive source and conclusion |
|---|---|
| Fixed location | `04-validate-handoff/autobahn/lib/observer.py:1573–1578` uses `root.parent/.omc/ai-catapult/gate-workspaces/<plan-goal-pr-head>` |
| HEAD materialization | `build_gate_workspace:1585–1605`, especially `:1601`, checks out the PR **head** detached into a new repository, with read-only borrowed objects and no remote/hooks |
| Gate invocation | `run_gates_in_workspace:1711–1733` builds/checks the copy and calls `run_local_gates(workspace, goal)`; `:1547–1567` supplies workspace root/cwd to base-copy gate scripts |
| HEAD-local contract | Base `local-ci.sh:23–33` invokes pinned `local_ci_contract.py:49–75`, which reads and SHA-validates the **workspace HEAD** contract/source/workflow files |
| HEAD-local execution | `local-ci.sh:68–74` forwards commands; base `ci-gate.sh:375–397` validates argv and executes in the workspace. HEAD `tests/run-tests.sh:59–62` invokes HEAD `tests/test-skills.sh` |
| Present failure | `test-skills.sh:39–44` filters absolute paths by `*/.omc/*`, excluding every candidate under the enclosing ancestor. `:283–288` warns/exits zero; unchanged `run-tests.sh:41–51,72–74` fails the full suite for zero reported assertions |

The unchanged current driver can consume corrected **HEAD-local discovery plus its HEAD source pin** during this goal's own certification; no driver installation must precede it. This is a viable static route, not runtime success. Actual same-command TDD, nonzero skill assertions, full local/hosted CI and signed certification remain future admitted work.

Moving the observer location is not selected: the candidate observer would not govern its own current-base certification, which still creates the old `.omc` path. Depending on that change after its own failing certification creates a cycle; a candidate-driver override violates provenance. Keep the existing location and every observed-root/workspace/git-metadata check.

## 4. Discovery and regression boundaries

Keep existing `find` traversal at the supplied `REPO_ROOT`, default no-follow behavior, exact `SKILL.md` matching and candidate type/order/visibility semantics. Compare a candidate's **literal root-relative key**, including its first component, against internal `.omc`, `.git` and `.claude` namespace components at every depth. An enclosing ancestor outside the root must not exclude the checkout. Emit the original filename expected by unchanged validators/display mapping, absolute when the observer supplies an absolute root.

Do not replace traversal with `cd` through a symlink root, add `-L`/`-H` or `-type f`, canonicalize a candidate target, interpret the root as an unquoted glob/regex, or weaken internal exclusions. Preserve spaces/tabs/backslashes with quoted literal-prefix removal and line reads/emission. Newline-bearing filenames retain the current line-oriented limitation; no new support or waiver is claimed.

Append regressions only to existing `tests/test-skills-validator_test.sh`, retaining all earlier cases/helpers/assertions. Its supplied-root fixture harness and unchanged `_test.sh` discovery already reach the full runner.

| Required admitted control | Result |
|---|---|
| Identical ordinary/ancestor `.omc` trees; enclosing `.git`/`.claude` | Same relative validated names, positive assertion totals and outcomes |
| Genuine invalid ordinary skill, including beneath `.omc` ancestor | Same nonzero result and diagnostic; validators/limits/exception lookup unchanged |
| Invalid internal/nested `.omc`/`.git`/`.claude` files plus a valid skill | Internal files never counted/validated; valid ordinary skill really checked; internal-only tree is zero-skill |
| Empty/internal-only full runner | Disposable unchanged runner refuses zero skill assertions with nonzero exit. Scratch positive-shell stand-in isolates this control only, never replaces a production suite |
| Whitespace and symlink characterization | Filenames remain unsplit; starting-root/file/directory symlink behavior equals reviewed base; no link following/target substitution |

Preserve direct skill-suite zero-skill warning/exit-zero behavior and the production full-runner's independent missing/zero-assertion refusal. Temporary fixtures/outputs stay outside observed root/workspace and cleanup-bound. No new runner, wrapper or fixture-file path is authorized.

## 5. Product and publication envelopes are distinct

The future product goal owns **only**:

| Path | Allowed work |
|---|---|
| `tests/test-skills.sh` | Discovery predicate/adjacent comment and original filename mapping only; validator bytes stay unchanged |
| `tests/test-skills-validator_test.sh` | Appended regression controls, earlier cases preserved |
| `.ai/ci/local-ci.json` | Re-pin existing skill-suite source key and add/re-pin only regression-home source key; keep `local-ci/1`, commands/workflows/all unrelated pins unchanged |
| `.ai/evidence/ACH-GW-DISC-01.json` | Own exact-subject/head-bound actual red/green evidence |

This **publication** changes only the new unique bound spec, one new immutable generation's producer-emitted `goals.json`, `sidecar.json`, `graph.json`, `handoff.md`, one appended v2 registration and additive live traceability/validation-report metadata. No product/test/evidence/CI-manifest edit, old-generation replacement, original registry-entry rewrite, claim retirement or v1-byte change belongs here. Traceability report proves only its stated graph checks, not product or hosted CI.

## 6. Retained ownership and future delivery

Retained metadata publisher: `ses_ef1f4424bffeaNnbfvk6XBn2At`; sole skills/main consolidator and parent queue: `ses_ef20636c4ffe0Ka0K3S4ZhLan4`; ACH coordinator: `ses_ef7f71673ffe0ciRXlP9fCqJjG`. E6's completed conditional registry/graph capacity and author non-contention are reused, not resumed or called an acquired full-path slot. Actual spec/generation/validation-report/registry/graph sequencing is recorded separately for the exact candidate. No second product writer is assigned.

Original author `ses_ef269e5b6ffeLKzDZxKbPsHj0I` and S-08 worktree/WIP remain retained/quiescent. Original approved generation `22d460b273badda208918248b877c362ea72585fd8269fcdb685e50b4e8645fa`, obligations, persistent claims and signed evidence remain untouched. Shared future CI source-pin work still needs the separately admitted implementation owner/window; a publication slot neither retires claims nor transfers WIP.

Reuse completed #118 evidence at `artifacts/consolidation-20261005/pr-118/`: its admission observations do not cure the absent certificate, `.omc` discovery failure or missing formal host review. Do not rerun unchanged doomed certification/full-suite attempts during this metadata continuation. The planning producer does **not** invoke that isolated suite: it simulates the target and observes classified planning gaps. Ordinary publication merge still requires fresh exact-head full local/hosted CI, independent review, formal host approval and current ordinary authority through the applicable planning replay lane; planning success alone proves none.

Both goal dependency arrays remain empty because the contract enforces intrageneration edges only. S-07 provenance/receipt verification and later qualified discovery receipt/ancestry are explicit procedural holds, not invented B5 completion. No O8/S-08/P5-02 product prerequisite is placed on discovery. Actual discovery product merge must precede S-08 publication/admission/WIP reuse; **discovery publication or product merge is not O8**.

Gates run ordinary same-uid/PATH PR subprocesses, without OS/network containment. Environment hygiene and post-gate detective checks do not fix the accepted intra-gate swap-and-restore LOW. No sandbox, egress denial, PATH redesign, cache/install guarantee or hash/assertion exception is added. Root HPG/guard and unrelated held lanes are unaffected.

After independent candidate review, resume the existing publisher separately for the publication/ordinary-merge gates. Only after actual publication may this goal obtain its own plan approval/live authority/implementation admission; only after actual discovery delivery may the S-08 successor advance. No old approval/signature, admin recipe, waiver or fabricated token supplies a missing stage.
