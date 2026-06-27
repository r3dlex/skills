# Standalone Fixture A

Reference v3 layout for a standalone repository. The tree below documents the expected files for a target repo at the standalone topology.

```
.
├── .ai/
│   ├── matrix.json
│   ├── system-prompts/
│   │   ├── architect.md
│   │   ├── developer.md
│   │   └── qa-engineer.md
│   ├── skills/
│   │   ├── git-ops.json
│   │   └── workspace-sync.json
│   ├── workflows/
│   │   ├── repo-workflow.md
│   │   └── repo-workflow.json
│   ├── phases/
│   │   ├── 01-discover-decide/status.json
│   │   ├── 02-govern-plan/status.json
│   │   ├── 03-configure-generate/status.json
│   │   └── 04-validate-handoff/status.json
│   ├── handoff/
│   │   └── init-ai-repo-handoff.md
│   ├── rules/
│   │   ├── security.md
│   │   └── technical-bounds.md
│   └── drift/
│       └── last-drift.json
├── .memory/
│   ├── human-override/
│   │   ├── custom-conventions.md
│   │   └── tribal-knowledge.md
│   └── self-learned/
│       ├── error-patterns.json
│       └── module-complexity.json
├── docs/
│   ├── architecture/
│   │   ├── adr/
│   │   │   └── 0001-init.md
│   │   └── data-contracts/
│   ├── specifications/
│   │   ├── ACTIVE/
│   │   └── ARCHIVED/
│   └── learning/
│       ├── concept-maps/
│       └── troubleshooting-matrix.md
├── AGENTS.md
├── CLAUDE.md
├── CONTRIBUTING.md
└── README.md
```
