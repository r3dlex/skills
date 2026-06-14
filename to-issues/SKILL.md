---
name: to-issues
description: Break a plan, spec, or PRD into independently-grabbable issues on the project issue tracker using tracer-bullet vertical slices. Use when user wants to convert a plan into issues, create implementation tickets, or break down work into issues.
---

# To Issues

Break a plan into independently-grabbable issues using vertical slices (tracer bullets).

The issue tracker and triage label vocabulary should have been provided to you — run `setup-skills` if not.

## Process

### 1. Gather context

Work from whatever is already in the conversation context. If the user passes a BRD, PRD, issue reference, work item ID, URL, or path as an argument, fetch it from the issue tracker and read its full body, comments, and traceability links.

### 2. Explore the codebase (optional)

If you have not already explored the codebase, do so to understand the current state of the code. Issue titles and descriptions should use the project's domain glossary vocabulary, and respect ADRs in the area you're touching.

### 3. Draft vertical slices

Break the plan into **tracer bullet** issues. Each issue is a thin vertical slice that cuts through ALL integration layers end-to-end, NOT a horizontal slice of one layer.

Slices may be 'HITL' or 'AFK'. HITL slices require human interaction, such as an architectural decision or a design review. AFK slices can be implemented and merged without human interaction. Prefer AFK over HITL where possible.

<vertical-slice-rules>
- Each slice delivers a narrow but COMPLETE path through every layer (schema, API, UI, tests)
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones
</vertical-slice-rules>

### 4. Publish

Publish issues/work items directly to the issue tracker in dependency order (blockers first), preserving BRD and PRD backlinks in each body. If the user asked for review first, show the list before publishing. Otherwise, publish with sensible defaults:

- **Granularity**: prefer many thin slices over few thick ones
- **Type**: default to AFK; mark HITL only when a human decision is genuinely required
- **Blockers**: express dependencies as a DAG, not a chain

For each slice, use the issue body template below. Apply the `ready-for-agent` triage label unless instructed otherwise.

<issue-template>
## Traceability

- BRD: <BRD ID/link, or "None provided">
- PRD: <PRD ID/link>
- Parent: <parent issue/work item, or "None">
- Version impact: <copy from PRD/spec, or "unknown">

## Parent

A reference to the parent issue/work item on the issue tracker (if the source was an existing issue, otherwise omit this section).

## What to build

A concise description of this vertical slice. Describe the end-to-end behavior, not layer-by-layer implementation.

Avoid specific file paths or code snippets — they go stale fast. Exception: if a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), inline it here and note briefly that it came from a prototype. Trim to the decision-rich parts — not a working demo, just the important bits.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Version impact

Copy the highest available PRD/spec/ADR/acceptance-criteria signal. If the slice appears lower-impact than the parent PRD/spec, keep the higher signal and note the conflict; do not downgrade from commit/diff inference alone.

## Blocked by

- A reference to the blocking ticket (if any)

Or "None - can start immediately" if no blockers.

</issue-template>

Do NOT close or modify any parent issue.
