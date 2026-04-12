# Writing Skill Descriptions

The description is the most important line in the skill. Claude uses it to choose
from potentially 100+ available skills. A bad description means the skill never fires.

## Rules

Write in third person. The description is injected into the system prompt.

Start with what the skill does, then add when to use it.
Pattern: "[Does X]. Use when [trigger condition]."

Be specific. Include key terms users would say.

Be slightly pushy. Claude tends to undertrigger. Overstate the trigger conditions
rather than understate them.

Max 200 characters for the description field.

## Good descriptions

```yaml
# Specific action + explicit trigger
description: Extract text and tables from PDF files. Use when working with PDFs, forms, or document extraction.

# Problem-oriented trigger
description: Use when tests have race conditions, timing dependencies, or pass/fail inconsistently.

# Technology-specific with clear scope
description: Use when using React Router and handling authentication redirects.

# Broad but bounded
description: Generate commit messages by analyzing git diffs. Use when the user asks for help writing commits or reviewing staged changes.
```

## Bad descriptions

```yaml
# Too abstract, no trigger condition
description: For async testing

# First person breaks discovery
description: I can help you with async tests when they're flaky

# Technology mentioned but skill is not specific to it
description: Use when tests use setTimeout/sleep and are flaky

# No action, just a label
description: Code review helper

# Too long, buries the trigger
description: This skill provides comprehensive assistance for reviewing code changes including but not limited to style, logic, performance, and security concerns across multiple programming languages and frameworks
```

## Description optimization checklist

After writing a description, verify:

1. Does it say what the skill DOES? (Verb in the first clause.)
2. Does it say WHEN to use it? ("Use when..." or equivalent.)
3. Is it third person? (No "I", "you", "we".)
4. Does it include terms users would actually say?
5. Would Claude pick this skill from 100 options for the right query?
6. Would Claude NOT pick it for an unrelated query?
7. Is it under 200 characters?

If any answer is no, rewrite.

## Trigger broadening technique

List 5 realistic user messages that should trigger this skill.
Extract the nouns and verbs from those messages.
Make sure at least 3 of those terms appear in the description.

Example for a PR review skill:
User messages: "review this PR", "check my pull request", "look at these changes",
"is this code ready to merge", "what do you think of this diff"
Key terms: review, PR, pull request, changes, merge, diff, code
Description: "Review pull requests and code changes. Use when checking PRs, diffs, or evaluating whether code is ready to merge."
