# Skill Structure

## YAML Frontmatter (required)

```yaml
---
name: skill-name
description: One line. Third person. What it does and when to use it. Max 200 chars.
---
```

`name` becomes the /slash-command. Use lowercase-kebab-case.
Use gerund form (verb + -ing) when the skill describes an activity:
`writing-tests`, `debugging-flaky-ci`, `reviewing-pull-requests`.

Use noun form when the skill is a reference:
`api-conventions`, `brand-guidelines`, `git-guardrails`.

## File size rules

No file exceeds 100 lines. If a file grows past 80 lines, split it.

SKILL.md is an overview. It answers: what does this do, when does it trigger,
what is the high-level process. It points to reference files for details.

Reference files hold the depth. API schemas, pattern libraries, code examples,
configuration details. Claude reads these on demand, not on every invocation.

## Progressive disclosure layers

Layer 1: Frontmatter (name + description). Loaded at session start for all skills.
Every session pays this cost. Keep descriptions tight.

Layer 2: SKILL.md body. Loaded when the skill is invoked.
Stays in context for the rest of the session (survives compaction up to 5K tokens).

Layer 3: Reference files. Loaded only when Claude reads them during the task.
Put large content here. Claude reads what it needs and skips the rest.

Layer 4: Scripts. Executed, not read into context.
Use for deterministic, repeatable operations (code generation, validation, formatting).

## What goes where

| Content | Location | Loaded when |
|---------|----------|-------------|
| Trigger conditions | Frontmatter description | Every session |
| Process overview | SKILL.md body | Skill invoked |
| API reference, schemas | references/*.md | Claude reads file |
| Code generation logic | scripts/*.mjs | Claude executes |
| Templates, fonts | assets/* | Claude copies |
| Good/bad examples | references/examples.md | Claude reads file |

## Platform considerations

Claude Code uses the Skill tool to load skills. Never use Read on skill files.
Codex uses `$skill-name` instead of `/skill-name`.
Gemini CLI uses `activate_skill`. Skills are auto-discovered.
Cursor loads `.cursor/rules/*.mdc` with `alwaysApply: true`. No slash command.
Copilot CLI uses the skill tool. Auto-discovered from installed plugins.
Platforms without hook support (Aider, OpenClaw, Trae) use AGENTS.md.

## Naming red flags

Too broad: `helper`, `utils`, `tools`. What does it help with?
Too narrow: `fix-auth-bug-in-line-42`. That is a task, not a skill.
Ambiguous: `manager`. Manager of what?
