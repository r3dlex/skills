# D13 comparison contract — held r3 text

Plan `e6-d13-comparison-contract`; sole goal `e6-d13-cc-01`; repository
`skills`. Proposed `readiness-contract/2`, live-mode publication. **Unpublished,
unapproved, unadmitted.** This is not a registered generation or an E6 successor.
No human approved these draft contents or code. The principal acknowledged only
one bounded text recovery and one review pair in
`.omc/plans/c2-bounded-recovery-acknowledgement-20261015.md`.

## Read first

1. D1–D13 remain in `docs/specifications/ACTIVE/e6-skills-legacy-ts-conversion.md`,
   SHA256 `981f1f80182180c02837d9eabba4f15f6383725bab89e67d713fc69dc4e01834`.
   This contract cites them; it edits neither that spec nor its registrations.
2. The principal selected a **separate reviewed add-only comparison contract**,
   not a D13 step-6 amendment: `.omc/plans/hitl-answers-20261014.md`, D13
   addendum, 2026-10-14T21:15:10Z. The purpose is narrowly to evaluate step 3's
   audit/export equality with `/provenance` asserted separately. Literal D13
   did not already allow this exclusion. No other disagreement is resolved.
3. The consumer remains goal `e6-sk-02-v1-port`, plan `e6-skills-ts-02`, generation
   `b287e55570671799d43ddf09a2af8c2247a5b7a5e8e6c859e91ed3f0431ed015`, AC-11
   “Provenance. The D13 procedure passes, steps 1–7.” Its spec/generation are
   not changed. This draft does not resume PR #139.
4. `source-capsule.json` identifies exact Git objects. Skills inspection pin:
   `4fa211b9e166983e50836a5b5b213de2acefb97a`. Historical root inspection pin:
   `aaa44dc48290d807634cbcaa0754444b3e8d8bd4`. Separately observed current local
   root HEAD/origin-main: `077cb6bd152f5ba38904b35b5c4f82d4d629e840` on
   2026-10-15. The latter never silently replaces the former. Local refs are
   not live-remote observations. No fetch, driver or validator ran here.

## Terms and source semantics

A **lane** is reference or candidate; a **target** is one repository/ref; a
**site** is `(repository, plan_id, operation)`; a **capture** is one lane's
stdout, stderr, exit, metadata and written-file observations at a site.

At the skills pin, `observer.py` SHA256
`b6c839d344e0f8adf05eb2bc0a825953ccf03a24752b727a9a83b74409e3047f`:

- `provenance()` (1017–1031) yields `source-lane` for different Git common
  directories. With equal common directories it first checks all driver
  manifest bytes against the target-ref blobs, refusing `driver_not_base_copy`
  on mismatch; only a successful check yields `base-copy`.
- Thus reference/candidate differ at the skills target, but both yield
  `source-lane` at the root, ai-catapult and ai-factory targets. Root's
  historical committed log contains 39/39 source-lane entries, not 39 captures
  of this proposed procedure.
- `audit-merges` appends to the log; `export-evidence` hashes/copies the whole
  log and is deliberately unlogged (B6, 3144–3145). Exports require serialized,
  quiescent collection. Export refusals may be generic `readiness-contract/2`
  envelopes without provenance (3268–3271).
- Hosted checks are queried at the PR head (916–921). A checker landing on
  main does **not** rerun old PR checks.
- `target_ref(main)` means `refs/remotes/origin/main` (587–588).
  `fresh_target()` additionally contacts origin (1239–1249). This comparator
  does not implement that network operation; qualified collection must supply
  independent live-freshness evidence or acceptance remains held.

The retained old-head feasibility pair (`34277a2a…` / `4ba14644…`, diff
`294762a64b51d410b3c4b30f58b740e8cfd9ac58d0dc433cc75878e9b7f9ea45`)
is historical incident evidence only, never a final-head D13 or CI pass.

## Inputs and custody: `d13-run/1`

The **consumer's** qualified runner owns collection and retention. The
comparator owns neither that runner nor `tests/fixtures/e6-v1-port`. Proposed
consumer retention is exclusively below
`tests/fixtures/e6-v1-port/d13/<run-id>/`, within goal 02's existing scope,
subject to security and scope review. Umbrella-only receipts are not enough
for clean-tree recomputation. Nothing is captured or written there now.

Each retained run contains:

```text
lanes.json                         d13-lanes/1
normalizations.json                [] for this generation
registries/<repository>.json        exact registry bytes at resolved revision
policies/<repository>.json          exact policy bytes at resolved revision
observation.json                    retained local Git observation transcript
captures/<lane>/<repository>/<plan_id>/<operation>/stdout
captures/<lane>/<repository>/<plan_id>/<operation>/stderr
captures/<lane>/<repository>/<plan_id>/<operation>/meta.json
captures/<lane>/<repository>/<plan_id>/<operation>/written-before/<path>
captures/<lane>/<repository>/<plan_id>/<operation>/written-after/<path>
raw-manifest.json                   sorted {path,bytes,sha256} inventory
```

`lanes.json` has `schema: d13-lanes/1`, `targets[]` of
`{repository,root,common_dir,target,ref,revision}`, plus reference/candidate
`{driver_root,common_dir,driver_commit}`. Roots/common directories are physical
absolute collection paths; commits are full 40-hex identities. For this
contract `target: main` has exactly `ref: refs/remotes/origin/main`; never
resolve an ambiguous bare branch or fall back to an older commit. The target
inventory is checked against the constant required repository IDs and the
independently qualified collection inventory, not inferred from capture folders.

Capture metadata retains `schema: d13-capture/1`, exact `argv`, `cwd`, integer
`exit`, run-wide positive `sequence`, UTC `started_at`/`finished_at`, lane
`driver_commit`, export `log_before`/`log_after` (`{sha256,lines}`), and complete
`written_before`/`written` maps (`{relative_path:sha256}`). Audit log/map fields
are null. Absent export directories produce `{}`; absent logs have null hash
and zero lines. Retain all stdout/stderr bytes, including empty streams;
retain written maps and file snapshots even after a nonzero export. Recompute
each map from its retained file bytes. A refusal never excuses written changes.

`raw-manifest.json` inventories every regular file above except itself, using
sorted repository-relative forward-slash paths, exact byte length and SHA256.
No symlinks, traversal, duplicate paths or unlisted files are accepted. Its
exact bytes have SHA256 `d13_contract.run_sha256` in consumer evidence; the
consumer evidence/report are outside the run, avoiding a digest cycle.
`run_directory` is repository-relative and physically contained in the scoped
fixture directory. Missing/extra/changed inputs fail, not a best-effort replay.

The observation transcript retains bounded read-only Git argv, roots, stdout,
stderr, exits and resolved identities for **all** targets and both drivers at
collection. It is part of the raw inventory. The runner, not this read-only
tool, writes it. It is an internal serialization of existing Git observations,
not a new driver API or permission to collect. Recorded absolute paths remain
historical labels during portable replay; they are not dereferenced or rewritten
as a claim of fresh CI observation.

Its schema is `d13-local-observation/1`, with `lanes_sha256` and `commands[]`.
Each command has `phase` (`start`/`finish`), unique subject (`target:<id>` or
`lane:<name>`), exact argv/cwd, exit, stdout/stderr as lossless base64 bytes.
The checker derives facts by parsing these raw responses, not a supplied `ok`
or `observed.git` flag. Require the fixed complete command set: for each target,
physical toplevel/common-dir and exact-ref commit resolution at start and finish,
plus start commit-existence, policy/registry blob IDs and their bytes at that
resolved commit; for each driver, physical toplevel/common-dir and HEAD at both
phases. All commands are the bounded local `rev-parse`, `cat-file`/`show` forms
corresponding to the assertions below. Reject unexpected/missing/duplicate
commands, wrong cwd/ref/object, nonzero required reads, malformed responses or
recorded start/finish mutation. A portable replay verifies the retained policy/
registry bytes and blob identities against those recorded responses; it does
not attest that the responses were authentically collected. Direct `--observe`
must perform the same complete reads against real local repositories and agree
with the transcript. The consumer's independent custody review authenticates
the transcript and its interval, not this reproducible parser.

**Security/custody stop:** retain no credentials, tokens, private keys or secret
material. Review safe exact bytes before retention; if an input contains a
secret, do not redact a payload and call it the original, or commit it to get a
pass. Hold the consumer until a lawful exact-scope collection/retention route
exists. Do not invent signatures or rewrite signed/historical objects.

## Tool and constants

`ts-tooling/src/d13-compare.mts` compiles under the existing build config to
`scripts/lib/d13-compare.mjs`, `.d.mts` and `.mjs.map`. Existing interfaces:

- `node scripts/lib/d13-compare.mjs <run> [--observe]`
- `node scripts/lib/d13-compare.mjs --contract`
- `node scripts/lib/d13-compare.mjs --consumer-check <evidence.json>`

Report exits are 0 pass, 1 red, 2 malformed/usage. Consumer mode reports failed
conditions, with 2 for malformed/missing required input and 1 for semantic,
identity, consistency or unavailable-history failures. Unsupported/unavailable
Node is never an expected tool refusal or a passing negative test.

The tool opens **no network connection**, invokes no driver and writes no file.
`--observe` uses bounded read-only local Git resolution/object reads.
`--consumer-check` additionally uses that same local Git facility for current
consumer HEAD, registration, blob and ancestry checks (`rev-parse`, `show`,
`cat-file`, `merge-base --is-ancestor`); this necessary lineage use is explicit,
not a hidden network extension. No `fetch`, `ls-remote`, checkout, ref update,
publication, certifier or host API is invoked. Only `node:`/relative sibling
imports; use existing process/byte utilities, not Python or a second runner.
Member-span handling stays in the new module; no sibling source edit is scoped.

| Constant | Fixed value |
|---|---|
| `schema` | `d13-comparison/1` |
| `excluded_fields` | `["/provenance"]` |
| `projected_schemas` | `["merge-audit/1","evidence-export/1"]` |
| `refusal_schema` | `readiness-contract/2` |
| `allowed_classes` | `["time-field","scratch-path","interpreter-diagnostic"]` |
| `permitted_sites` | `{"merge-audit/1":[],"evidence-export/1":[]}` |
| `required_targets` | `["skills","aitool-root","ai-catapult","ai-factory"]` |
| `argv_template` | `["bash","04-validate-handoff/autobahn/contract-run.sh","<operation>","--root","<target.root>","--target","<target.target>","--plan","<plan_id>"]` |
| `consumers` | `[".ai/evidence/e6-sk-02-v1-port.json"]` |
| `spec_sha256_lineage` | published contract spec SHA256 only; unknown until lawful publication |
| `superseded_tool_sha256` | `[]` |

Every extension needs its own reviewed add-only generation. Caller declarations
never extend masks, sites, targets, consumers or lineage. No prior-tool bypass:
even an eventually authorized historical digest must have a matching retained
implementation capable of full recomputation; a public hash alone never passes.
This first generation accepts only its actual merged checker bytes.

## Projection — unchanged boundary

For either projected schema, require exactly one depth-one string member
`provenance`, valued `base-copy` or `source-lane`. Locate its **member byte
span by a depth-one JSON walk**, never indentation/regex. Remove only that
member's line-leading whitespace, literal key token, colon-space, string token,
trailing comma and LF. The span must contain exactly that rendering and nothing
else (observer indent-2/sorted-key output, where `schema` follows provenance).
Failure is `projection-unique`; an absent/invalid value is `provenance-expected`.
Nested members, inline extra payload and every byte outside that depth-bound
span remain compared. Duplicate depth-one keys cannot select a convenient span.

`permitted_sites` is empty: `normalizations.json` must be `[]`. Any caller mask,
including an allowed class at `/refusals/0/detail`, `/prs/0/merged_at` or a
stderr prefix, is malformed, not applied. Generic refusal envelopes are compared
unchanged; other stdout schemas/nonobjects are `envelope-schema` red. Compare
stdout projections and stderr as byte buffers and exits exactly. Never decode
invalid bytes with replacement, reserialize payload JSON or sort it for equality.
Differences may be explained by JSON pointer, otherwise by first byte offset.

## Assertions and report derivation

Assertions have stable `(id,subject)` identities, `ok` and `detail`; enumerate
all required assertions, including global ones, once. A site is `equal-success`
only when both exits are zero and its assertions/equalities hold;
`equal-refusal` only when both are nonzero and they hold; otherwise `red`.
Equal refusals are never successes. A failed global assertion makes the whole
report red even if no site-classification count is red.

### Lanes

- `provenance-expected`: per lane/target, common-dir equality implies expected
  base-copy only conditional on the driver's manifest-byte check succeeding;
  otherwise expected source-lane. Every provenance-bearing envelope matches.
- `lanes-distinct-own-repository`: exactly the skills target shares reference
  common-dir; its observed reference/candidate values are base-copy/source-lane.
- `provenance-pair`: both site envelopes bear provenance or both are generic
  refusals; mixed pairs are red.
- `lane-observed-per-target`: every target has a provenance-bearing pair.
  Additionally `audit-pair-per-target` requires at least one **merge-audit/1**
  pair per target with actual target revisions in both lanes. Export-only
  observation or generic audit refusals cannot substitute. If real history
  supplies no qualifying audit pair, hold; do not forge one or ignore the target.
- `common-dir-reference`: exactly one target equals reference common-dir.
  `common-dir-candidate`: candidate equals no target and differs from reference.
- `driver-commits-distinct`: full distinct lane commits; each capture agrees.
- `observe-git`: under `--observe`, physical root/toplevel/common-dir identities,
  actual driver HEADs and commit existence match the manifest. Truthful metadata
  for a linked candidate worktree satisfies this assertion; separate-clone
  independence is a different assertion.

### Every target, ref, registry and site

`--observe` performs these checks unconditionally for **every** requested target,
before relying on any envelope (including when every capture is a refusal):

1. `target-repository-bound`: resolve physical `target.root` to its actual Git
   toplevel/common-dir; compare the qualified inventory identity and recorded
   metadata. Read `.ai/policies/readiness-policy.json` at the resolved revision;
   require its `repository.id` equals the target's repository ID. A policy/1
   identity is not presumed to have policy/2's `target` field. Missing identity,
   wrong repository, symlink/root substitution or conflicting identity fails.
2. `target-ref-bound`: resolve the exact local fully qualified `target.ref`
   once, to a commit; require it equals `target.revision`. Pin that object for
   every subsequent policy/registry read. At completion re-observe the **same**
   ref and root/Git identities; mutation or disappearance is red, never a retry
   at a more convenient revision. Older existing commits are not substitutes.
3. `registry-bound`: byte-copy equality to the registry blob at that pinned
   commit, and policy-copy equality to the policy blob there. Record blob IDs
   and SHA256 values. Registry copies cannot determine their own valid revision.
4. `targets-complete`: each required ID occurs exactly once; additional targets
   are recorded and receive all checks, never silently ignored.
5. `site-set`: every registry `plans[]` entry, all statuses, times both
   operations, in both lanes, exactly; reject duplicate entries/sites, jointly
   omitted plans and omitted targets.
6. `target-revision`: every merge-audit envelope has the pinned target revision;
   the per-target audit pair must expose it. `envelope-operation` binds audit
   versus export schemas; generic refusals remain permitted subject to the pair
   rule. `envelope-plan` binds every present plan/generation to its site's
   registry entry. `capture-argv` requires the fixed template and lane cwd.

The report's Git evidence is **local**. It does not show that origin is currently
at that ref, nor that supplied roots are the lawfully intended remote. Independent
collection must bind credential-free repository identity, target inventory,
remote/ref readback and collection interval. If qualified live readback is
unavailable or not in the lawful consumer capability, live freshness remains
unready. Do not introduce `ls-remote` into the comparator or weaken old binding.

### Outcomes, ordering and raw evidence

- `exit-equal`, `refusal-codes-equal`, `finding-codes-equal`: exact exits and
  sorted code lists (empty when absent).
- `projection-equal`, `stderr-equal`: byte equality, not semantic reformatting.
- `written-equal`: complete export after-maps equal on **all** exits; maps are
  nonempty on successful exports. Before/after snapshots/map hashes and changes
  remain in raw evidence and report; differing refusal writes are red.
- `captures-serialized`: sequence unique/positive, each next start at/after
  previous finish; all intervals valid. `order-audits-before-exports`: per
  target, all completed audits precede all exports in both lanes.
- `log-quiescent`: each export's before/after log sample equal, and both lanes'
  samples equal at a site. These samples and schedules are consistency evidence,
  not independent proof that no unobserved intervening process ran.
- `raw-inputs-bound`: complete manifest and every stream, metadata, registry,
  policy, observation and written snapshot digest/length/map recompute.

Root's historical GAP.md (`5af7c029…`) records `evidence_incomplete`; a
conflicting prior export may honestly yield `evidence_conflict`. No operator
deletes, pre-creates, back-dates or rewrites exports, logs, tags, certificates,
signatures or trust anchors to change the comparison. Missing certificates
remain missing; equal refusal is not historical successful export proof.

The full deterministic `d13-comparison/1` report contains `assertions`, all
`contract` constants plus running `tool_sha256`, `counts`, `lanes` with expected
values by target, `observed` (`git`, `basis: retained-local-observation`, full
facts/problems), `run` (repository-relative path and every input digest),
`schema`, every `sites[]` entry and `verdict`. Each site carries identity,
classification, both raw stream/map/metadata digests and exits, codes, provenance,
projection digests, normalizations applied (empty) and byte differences.
Counts are derived: sites length; exact classification totals summing to that
length. Verdict is malformed for malformed input, otherwise pass iff all
required assertions hold and no site is red. No empty assertion/site shortcut.

Use one deterministic report function over raw bytes, retained observation facts
and exact checker constants, with canonical key ordering and deterministic array
order. `--observe` additionally re-executes the bounded local Git observations
and requires exact agreement with the retained transcript before it can report
`observed.git: true`. A later portable replay derives **the same entire report**
from those retained facts; it does not set `observed.git` from a caller's flag.
Its result describes recorded observation consistency, not new Git observation
at archived absolute paths. Fresh consumer Git facts go in the separate consumer
check result, never relabel the original report or its capture time.

## Consumer check: recomputation, exact dependency and fresh validation

Consumer `d13_contract` requires spec digest, exact generation, publication
commit, actual goal merge commit, merged tool blob ID and SHA256, run directory
and manifest SHA256, complete report plus canonical report-stdout SHA256,
collection/custody receipt paths+digests, and an independently collected
dependency-completion record. Missing/malformed input exits 2. None of these
self-declarations establishes its own authority.

The retained completion record names repository/host locator, plan, generation,
goal, exact policy-derived branch, PR number, base target, PR head, actual merge
commit, publication commit, merged tool path/blob/SHA256, independently observed
source locator/time and the collecting party. Its digest is bound in consumer
evidence. The mechanical comparisons below cross-check those values against
Git/registration and the selected evidence; the independent reviewer must
qualify the actual hosted source/collector and record that decision separately.
A self-authored completion record, including one with perfectly matching local
values, is not a qualified completion receipt. If no independent source can be
established, the dependency stays unready rather than treating this record's
presence as completion authority.

`--consumer-check` must implement all of the following, not field-presence tests:

1. Load only physically contained retained inputs. Verify the complete raw
   inventory and re-run every comparison assertion, including recorded target
   bindings, stream bytes, refusal writes, site classifications and global
   assertions. Derive counts/verdict from assertions/sites. Reject an internally
   inconsistent embedded report even before checking its claimed pass.
2. Serialize the recomputed **whole** report and require exact canonical bytes
   and report SHA256 equal the embedded report; compare every field, not a
   selected projection. The recomputation must itself be pass with recorded
   Git observation true. The r2 forgery (red raw/report, but verdict→pass,
   red-count→0, observed.git→true and valid public hashes) must fail.
3. In the actual consumer Git tree, resolve HEAD and the exact local target ref,
   pin/re-observe them for movement. Read the registry and immutable generation
   objects from that target, not caller copies or the checkout. Require exactly
   `northstar-plan-e6-d13-comparison-contract`, the exact selected generation,
   repository `skills`, expected spec path and bytes, bundle identity, goal
   `e6-d13-cc-01` and artifact digests. Recompute the registered generation using
   its frozen bundle/spec/policy/anchor identity, not a merely known spec hash.
   Require the same exact registered identity in the consumer tree. Wrong
   generation or spec fails, even if both are independently real registrations.
4. Match publication/merge identities against the independently collected
   completion record for this **exact** goal PR/branch/target and generation.
   Mechanically verify publication precedes the claimed merge, merge ancestry
   of the pinned target and consumer/capture heads, and tool blob identity at
   the actual merge. SHA256 means the blob's file bytes, not the Git blob ID.
   The running committed checker, embedded report and merged tool bytes must
   agree, with compiled drift separately gated. A wrong blob, unrelated commit,
   pre-publication completion, missing object or unavailable/shallow ancestry
   fails. An ancestor with coincidentally equal bytes is not by itself proof
   that the named goal completed.
5. Bind current capture lineage: candidate capture commit must include the
   contract goal merge and checker, and carry the same driver artifact bytes
   as the tested consumer head. If evidence is committed in a later evidence-only
   commit, record both identities and compare the full executed driver artifact
   inventory; any product drift requires new collection. An old/pre-contract
   head's captured flags/checks cannot satisfy this condition.
6. Emit `d13-consumer-check/1` with failed condition IDs, current local HEAD,
   target/registry/generation/spec/merge/tool identities, raw/report digests,
   `recomputation` and `local_lineage` outcomes, and explicitly
   `capture_authenticity: unverified` / `live_remote_freshness: unverified` unless
   independently established outside this tool. A mechanical exit 0 means
   consistency/local identity only, never consumer admission or full D13 pass.

**Independent review duties are mandatory.** Consumer reviewers must verify the
dependency record against a qualified independent hosted completion source
(exact repository, goal branch, PR, head, target, merge commit, generation and
publication), not accept the evidence author's claim. Verify authentic driver
collection/custody on the required anchor host: collector/source authority,
actual executable bytes and commits, argv/cwd, target inventory and live-ref
readback at collection, serialized completed intervals, raw input manifest and
unbroken transfer into the consumer tree. Use applicable existing assurance
and signature requirements; invent no new certificate, principal or signature.
An internally consistent forged run can pass recomputation: missing independent
provenance/custody/live-freshness evidence therefore keeps the consumer unready.
These duties are not claimed mechanically authenticated by a file hash.

**Fresh enforcement point.** Only after separate lawful continuation authority,
goal 02's custodian integrates current main by the existing **merge-commit**
rule, carrying the actual merged checker/test. It then supplies current qualified
capture evidence in its own scope. At that future head, the new test runs
`--consumer-check` for every present `consumers` file; nonzero is a suite failure.
`tests/test-scripts.sh` discovers it via `tests/run-tests.sh`, the hosted required
`Test Suite` at the actual tested PR head. The consumer's own admission/review
requires its evidence file; main without that file reports absence and skips
only that unrelated consumer check, not consumer readiness. Reviewers independently
require fresh hosted/local check receipts for that exact consumer head and its
current target; old #139-head checks, main checks and archive flags do not count.
If the new test is not actually in the head or a new check has not run, this
enforcement point has not occurred. No retrospective auto-trigger is promised.

Recomputation uses the retained observation transcript portably, so clean-tree
CI need not recreate archived absolute driver paths or contact target remotes.
It must have actual consumer Git history/registration/tool objects for local
lineage. External authenticity/live-freshness verification is separate and may
still block acceptance after a green suite. If the existing lawful collector or
independent completion source cannot furnish this evidence within consumer
scope/capabilities, **HOLD**, not a new API/network/repository writer or a weaker
acceptance criterion. No historical tool/spec allowlist waives recomputation.

`dependencies: []` remains: cross-plan goal dependencies are unsupported and
the edge points from goal 02 to this goal. Goal IDs stay stable. Optional future
goal-02 republication cannot rewrite its old generation and remains constrained
by the open/merged PR replacement rule. Goals 03/04/07 may cite a later contract
in their own publications; this plan does not bind them or permit new masks.

## Sole implementation slice — seven literal paths

```text
.ai/evidence/e6-d13-cc-01.json
scripts/lib/d13-compare.d.mts
scripts/lib/d13-compare.mjs
scripts/lib/d13-compare.mjs.map
tests/e6_d13_comparison_test.sh
tests/fixtures/e6-d13-cc
ts-tooling/src/d13-compare.mts
```

These are the original all-new/add-only paths, absent at the skills pin.
Consumer raw capture/evidence files are **not** added to this scope. Existing
goal 02's broad `ts-tooling` prefix is disclosed: use the registered lane-matrix
exact-file coexistence precedent (261–271); never two open PRs on one file.
The recorded #139 29-file list and HPG/H1 12-path scopes are disjoint at the
inspection base; current window/scope must be rechecked later, not assumed.
No sibling library, manifest, policy, ledger, `.ai/ci/local-ci.json`, hook,
bound spec, generation, source pin or #139/H1/HPG file is released for editing.
Publication spec/registry/traceability surfaces require their own later window;
they are not implementation scope.

## Acceptance criteria (mirrored in goals.json)

1. **Dispatch/coexistence:** re-observe O8
   `f5e338b92bb754c2bfffdf542b498530258fdbc0` ancestry and exact-file coexistence
   at future admission. This is not an E6 successor or a source-authority waiver.
2. **Tool/constants:** implement the three interfaces, exits and fixed constants
   above; no network/driver/write; only bounded local Git for observation and
   consumer lineage. No superseded-report bypass or sibling source edit.
3. **Projection:** exact depth-one member span only, nested bytes preserved,
   permitted sites empty, caller masks malformed, all other payload/stderr/exit
   bytes compared. Equal generic refusals stay refusals.
4. **Assertions:** implement every lane, target/ref/repository/registry/site,
   operation/plan/argv, outcome, written-map, ordering, quiescence and raw-binding
   assertion; exact deterministic whole-report derivation and recomputation.
5. **Fixtures:** P1; M01–M34; O01–O09 and C01–C15 below. Truthful linked candidate:
   common-dir-candidate fails, observe-git passes; separate false-metadata case:
   observe-git fails. Positive consumer uses the actual temporary-Git --observe
   report and digest-bound run, not injected flags/hashes. All fixture artifacts
   are labelled synthetic; none supplies real capture authenticity.
6. **TDD:** fixtures and test present, compiled module absent, same command
   `bash tests/e6_d13_comparison_test.sh` red exit 1 then green after lawful
   implementation. Record per-case assertion outcomes and checker SHA256 in
   `.ai/evidence/e6-d13-cc-01.json`; run all five verification commands at the
   eventual PR head. Nothing is run or certified in this held planning lane.
7. **Strict stack:** D5 strict tsc, eslint complexity 10/cognitive 15,
   no-floating-promises, zero warnings/suppressions, build drift; plain Bash
   test passes shellcheck -S error, shfmt -d and bash -n. No Python/legacy growth
   or bridge. If TSF-04 applies, retain E6 goals 05/07 as replacement owner under
   the registered tswc-rt-a6 reconciliation; do not invent an exemption.
8. **Consumer edge:** implement all six consumer-check conditions and the fresh
   future consumer-head enforcement point; exact registered generation/spec,
   actual goal merge/tool blob and ancestry, raw/report consistency, independent
   completion/capture custody/live-freshness review. Missing trust evidence holds
   the consumer even when mechanical checks pass. No #139 continuation here.

## Fixture inventory — future tests, no execution claim

P1: four required targets; skills distinct lanes; consumers both source-lane;
one qualifying audit pair per target; at least two equal-refusal exports, one
`evidence_incomplete`, one `evidence_conflict`; empty normalizations, serialized
captures, stable export logs and complete before/after written maps/snapshots.

| Mutation | Required failing assertion/outcome |
|---|---|
| M01 nonexcluded byte | projection-equal |
| M02 absent provenance | provenance-expected |
| M03 both skills lanes base-copy | lanes-distinct-own-repository |
| M04 inverted lanes | provenance-expected |
| M05 exit drift | exit-equal |
| M06 refusal-code drift | refusal-codes-equal |
| M07 one-lane missing site | site-set |
| M08 undeclared merged_at drift | projection-equal |
| M09 time-field declaration | malformed, exit 2 |
| M10 shared candidate common-dir | common-dir-candidate |
| M11 stderr byte | stderr-equal |
| M12 successful-export written drift | written-equal |
| M13 audit between exports | order-audits-before-exports |
| M14 cross-lane log drift | log-quiescent |
| M15 generic/projected mixed pair | provenance-pair |
| M16 all-generic consumer target | lane-observed-per-target |
| M17 unknown normalization class | malformed, exit 2 |
| M18 duplicate depth-one provenance | projection-unique |
| M19 audit target-revision drift | target-revision |
| M20 nonobject stdout | envelope-schema |
| M21 finding-code drift | finding-codes-equal |
| M22 unanchored reference common-dir | common-dir-reference |
| M23 equal driver commits | driver-commits-distinct |
| M24 nested provenance drift, misleading indentation | projection-equal |
| M25 scratch-path at refusal detail | malformed, exit 2 |
| M26 interpreter-diagnostic stderr declaration | malformed, exit 2 |
| M27 jointly omitted required target/captures | targets-complete |
| M28 audit envelope at export site | envelope-operation |
| M29 wrong plan envelope | envelope-plan |
| M30 wrong argv plan | capture-argv |
| M31 export before/after log drift | log-quiescent |
| M32 overlapping intervals | captures-serialized |
| M33 refusal-export written drift | written-equal |
| M34 extra content in excluded member span | projection-unique |

Build observation cases **later at test time** using four temporary Git target
repositories with committed registries/policies and independent driver clone:

| Case | Required result |
|---|---|
| O01 separate candidate clone, accurate data | pass, observe-git true |
| O02 linked candidate worktree, truthful metadata/envelopes | common-dir-candidate red; observe-git passes |
| O03 false common-dir/HEAD metadata | observe-git red |
| O04 registry copy omits a committed plan | registry-bound red |
| O05 old valid revision/registry has fewer plans than requested ref | target-ref-bound red |
| O06 right-looking captures but wrong root/policy repository ID | target-repository-bound red |
| O07 exact requested ref moves/disappears during observation | target-ref-bound red |
| O08 generic audits with only provenance-bearing export pair | audit-pair-per-target red |
| O09 jointly omitted site in both lanes and smaller registry copy | registry-bound/site-set red |

Consumer cases reuse O01's **actual generated observed report**, raw manifest,
temporary local registered generation/spec/tool objects and synthetic qualified
completion record. Never obtain a positive by injecting tool hashes into P1:

| Case | Required result |
|---|---|
| C01 complete observed O01 run, exact local lineage | mechanical exit 0; authenticity/live-remote still unverified |
| C02 missing d13_contract | malformed exit 2 |
| C03 genuine red report/raw run | exit 1 |
| C04 wrong running/merged tool SHA or blob | exit 1, dependency-tool |
| C05 wrong registered spec digest | exit 1, dependency-spec |
| C06 r2 red→pass forgery with public hashes/flag/count edits | exit 1, report-consistency/recomputed-report |
| C07 changed assertion/site/classification/count or omitted assertion | exit 1, report-consistency/recomputed-report |
| C08 changed/missing/extra raw stream, metadata or written snapshot | raw-inputs-bound failure; missing/malformed input 2, digest mismatch 1 |
| C09 wrong generation, including another valid one | exit 1, dependency-generation |
| C10 unrelated/pre-publication claimed goal merge | exit 1, dependency-ancestry/completion mismatch |
| C11 unavailable objects/shallow history | exit 1, dependency-history-unavailable |
| C12 old/pre-contract consumer/capture/check head | exit 1, consumer-head-binding |
| C13 absolute archived paths replayed without fresh dereference | recomputation only; no fresh-Git/CI/authenticity claim |
| C14 absent/unqualified independent completion/capture/live evidence | goal remains unready, regardless of mechanical consistency |
| C15 consumer path present fails / absent on unrelated main | present fails suite on nonzero; absence reported, never consumer readiness |

Mutations change one documented semantic feature, updating dependent raw digests
when needed to reach that assertion; additional failures are permitted. Assert
the named condition/code and exact exit, never generic nonzero or node failure.
The test ends `Results: PASS=<n> FAIL=<m>`. Synthetic fixture Git observations
prove test behavior only; they do not authenticate any real D13 capture.

## Future verification and TDD procedure

Unchanged `verification[]` (scripts exist at the inspection base):

- `bash tests/ts_tooling_test.sh`
- `bash tests/legacy_freeze_test.sh`
- `bash tests/run-tests.sh`
- `prek run --all-files`
- `git diff --check`

The new test is not in that array because it is absent at the publication base;
existing test discovery reaches it. After separate authorization/admission:
write fixtures/test first, observe module-absent red, implement/build the scoped
module, observe same-command green and all verification at exact head, record
evidence. No command above was run for this planning recovery. No coverage
percentage, successful validator, approval, generation or implementation result
is inferred from text/JSON review.

## Remaining holds and non-goals

Review pair is not run in this author session. At most APPROVE_HELD_DRAFT from
both independent roles could accept this held text; not convergence, publication
or implementation readiness. Any REQUEST_CHANGES/BLOCKED parks it; no r4 cure.
Registration, exact generation/digests, fresh own-plan approval/admission, current
publication window, qualified source/capture trust and full local/hosted gates
are future requirements. HPG/H1/source-gw custody is not released. Human SQ3
still orders source gw-* after actual HPG landing; the root #131 failed-gate
fallback is not authorized. No #139/#130/product/test/source edit, driver,
capture generation, publisher, registry/tag/approval/engine/PR/push/certify/merge.

Knowledge kind: `plan`. `unpublished: held` — explicit principal scope forbids
publication. Skills has no knowledge registry at the inspected pin; root's
registry is not authority to publish this child-repository planning record.
