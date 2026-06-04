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
- `Out of scope`

### Ticket/work item

- `BRD link`
- `PRD link`
- `Parent link`
- `What to build`
- `Acceptance criteria`
- `Blocked by`
- `Verification`

## Skill handoffs

- `to-prd` consumes a BRD link/ID when present and writes it into the PRD Traceability section.
- `to-issues` copies BRD and PRD backlinks into every generated ticket/work item.
- `triage` preserves traceability fields while changing state/labels/tags.
