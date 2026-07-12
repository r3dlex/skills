# BRD/PRD Traceability Module

Read when the repo needs a visible path from business need to implementation tickets and drift verification.

## Artifact chain

1. **BRD** — captures business problem, measurable outcome, stakeholders, constraints, risks, and success metrics.
2. **PRD** — references the BRD, translates business outcomes into user stories, acceptance criteria, implementation decisions, and testing decisions.
3. **Tickets/issues/work items** — reference both BRD and PRD, slice implementation as tracer bullets, and carry acceptance criteria.
4. **Agent brief** — references the ticket, PRD, relevant ADRs, Archgate rules, and verification commands.
5. **Drift report** — checks PR diff against BRD, PRD, acceptance criteria, ADRs, and `.rules.ts`.

## Minimum fields

### BRD

- `BRD ID`
- `Business problem`
- `Target users/stakeholders`
- `Desired outcomes / metrics`
- `Constraints and non-goals`
- `Risks and open questions`

### PRD

- `PRD ID`
- `BRD link`
- `Problem statement`
- `Solution`
- `User stories`
- `Acceptance criteria`
- `Implementation decisions`
- `Testing decisions`
- Optional `versionImpact` metadata (`major|minor|patch|none`) when the product owner wants an explicit release-impact claim; release tooling must still infer impact from PRD/spec prose when this field is absent.
- `Out of scope`

### Ticket/work item

- `BRD link`
- `PRD link`
- `Parent link`
- `What to build`
- `Acceptance criteria`
- `Version impact` — copy the highest available PRD/spec/ADR signal; do not infer a lower impact from commits when the product spec says otherwise.
- `Blocked by`
- `Verification`

## Version-impact signal precedence

Use a **highest-signal-wins** rule whenever release/versioning behavior needs a version-impact decision:

1. Explicit PRD, product spec, acceptance criteria, or ADR compatibility statements.
2. Ticket/work-item version-impact fields copied from the PRD/spec chain.
3. Conventional-commit or diff inference.
4. Operator defaults or unknown impact.

If signals conflict, preserve every signal in the audit record and select the highest-priority source above. Do not downgrade a PRD/spec breaking-change signal because commits look non-breaking.

## Skill handoffs

- `to-prd` consumes a BRD link/ID when present and writes it into the PRD Traceability section.
- `to-issues` copies BRD and PRD backlinks into every generated ticket/work item.
- `triage` preserves traceability fields while changing state/labels/tags.
- `ai-catapult-init` release versioning consumes PRD/spec prose and optional `versionImpact` metadata as auditable inputs; incompatible explicit claims must be recorded for review before tagging.
