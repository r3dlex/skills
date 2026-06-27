# Skills Ecosystem

A portable collection of agent skills organized around progressive disclosure — each skill exposes just enough to trigger correctly, then progressively reveals detail as needed.

## Language

### Core Concepts

**Skill**:
A self-contained agent capability defined by a SKILL.md file with frontmatter metadata and a workflow body. Skills are portable across repos and Claude Code installations.
_Avoid_: Plugin, extension, tool, command

**Progressive disclosure**:
The design principle where a skill reveals information in layers: Layer 1 (frontmatter description) triggers the skill, Layer 2 (SKILL.md body) provides the workflow, Layer 3 (REFERENCE.md) adds deep detail on demand.
_Avoid_: Lazy loading, just-in-time docs

**Layer**:
One of three concentric documentation rings. Layer 1 is the `description` frontmatter field (< 150 words). Layer 2 is the SKILL.md body (< 100 lines). Layer 3 is REFERENCE.md and companion files (unlimited size).
_Avoid_: Tier, level, section

### Agent Roles

**AFK**:
"Away From Keyboard" — work an agent can complete and merge without any human interaction. AFK issues are fully specified with testable acceptance criteria.
_Avoid_: Autonomous, unattended, automated

**HITL**:
"Human In The Loop" — work that requires a human decision, design review, or manual verification before it can proceed.
_Avoid_: Manual, gated, approval-required

**Agent brief**:
A structured comment on an issue that gives an agent everything it needs to implement the fix without additional context: what to build, acceptance criteria, codebase pointers, and testing guidance.
_Avoid_: Handoff, spec, task description

### Issue Workflow

**Triage**:
The process of evaluating an incoming issue, assigning a category (`bug` / `enhancement`), and moving it through a state machine (`needs-triage` → `needs-info` → `ready-for-agent` / `ready-for-human` / `wontfix`).
_Avoid_: Review, assessment, prioritization

**Tracer bullet**:
A thin vertical slice that cuts through ALL integration layers end-to-end. Each slice is independently demoable and verifiable. Contrasts with horizontal slices that span one layer across many features.
_Avoid_: Thin slice, end-to-end story, vertical feature

**Vertical slice**:
Synonym for tracer bullet — a complete, narrow path through every layer (schema, API, UI, tests).
_Avoid_: Horizontal slice, layer-at-a-time

**Out of scope**:
A knowledge base (`.out-of-scope/`) recording rejected enhancement requests and the reasoning, so duplicate requests can be identified and resolved quickly.
_Avoid_: Won't do, rejected, backlog-denied

### Documentation Artifacts

**CONTEXT.md**:
A domain language glossary at the repo root defining canonical terms for the project's problem space. Contains no implementation details — it is a glossary, not a spec or scratch pad.
_Avoid_: Glossary, terminology doc, domain model

**ADR**:
Architecture Decision Record — a document capturing a hard-to-reverse decision, its context, alternatives considered, and consequences. Stored under `docs/architecture/adr/`. Only warranted when the decision is hard to reverse, surprising without context, and the result of a real trade-off.
_Avoid_: Design doc, tech spec, decision log

**PRD**:
Product Requirements Document — a structured issue describing the problem, solution, user stories, implementation decisions, testing strategy, and out-of-scope items for a feature.
_Avoid_: Spec, requirements doc, feature brief

### Engineering Concepts

**Deep module**:
A module that encapsulates substantial functionality behind a simple, stable interface that rarely changes. The best modules have high depth-to-interface ratios. Contrast with shallow modules that expose complex interfaces for trivial functionality.
_Avoid_: Fat model, rich domain object, service layer

**Domain glossary**:
The canonical vocabulary for a project, captured in CONTEXT.md. All agent output (issue titles, PR descriptions, commit messages, ADRs) must use glossary terms, never synonyms.
_Avoid_: Ubiquitous language, terminology, naming conventions

**Interface design**:
The practice of designing module boundaries that are deep (simple interface, complex implementation) rather than shallow (complex interface, trivial implementation). Good interfaces minimize what callers need to know.
_Avoid_: API design, contract design

## Example Dialogue

**Dev**: I want to add a new skill for deploying to our staging environment.

**Domain expert**: Is this a workflow skill (Layer 2 body describes a process) or a reference skill (mostly Layer 3 detail files)?

**Dev**: Workflow — it's a step-by-step deployment process.

**Domain expert**: Then keep Layer 2 under 100 lines. Put environment-specific config in a REFERENCE.md at Layer 3. Make sure the frontmatter `description` clearly states when this skill triggers so agents don't invoke it for production deploys. Is this AFK (fully automated deploy) or HITL (needs human approval)?

**Dev**: HITL — someone needs to approve before it hits production.

**Domain expert**: Then label it as HITL in the workflow and include the gate step explicitly. The triage label `ready-for-human` might apply here — deployment decisions that need judgment.
