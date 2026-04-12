# Testing Skills

## Core principle

If you did not watch an agent fail without the skill, you do not know
if the skill teaches the right thing.

Untested skills have issues. Always. 15 minutes of testing saves hours of debugging.

## TDD for documentation

The same RED-GREEN-REFACTOR cycle applies to skills:

RED: Write test cases (pressure scenarios). Run them without the skill.
Watch the agent fail or produce suboptimal output.

GREEN: Write the skill. Run the same test cases with the skill loaded.
Watch the agent succeed.

REFACTOR: Tighten the skill. Remove redundant instructions.
Verify tests still pass.

Write the tests BEFORE writing the skill. If you write the skill first,
delete it and start over. You cannot test what you already taught.

## Description trigger testing

Create 20 eval queries. Mix of should-trigger and should-not-trigger.
Save as JSON:

```json
[
  {"query": "help me write a commit message for these changes", "should_trigger": true},
  {"query": "what is the capital of France", "should_trigger": false},
  {"query": "review my PR before I merge", "should_trigger": true},
  {"query": "how do I install node.js", "should_trigger": false}
]
```

Queries must be realistic. Include file paths, personal context, abbreviations,
typos, casual speech. Mix lengths. Focus on edge cases, not clear-cut examples.

Run the eval. If accuracy is below 90%, revise the description.

## Subagent behavior testing

For task skills, run 3-5 test scenarios using subagents:

1. Define the scenario (input state, user request)
2. Dispatch a subagent with the skill loaded
3. Evaluate the output against expected behavior
4. Record pass/fail with the specific failure reason

Each test scenario should exercise a different aspect:
the happy path, an edge case, a boundary condition, a common mistake.

## Skill quality checklist

After testing, verify:

1. Does the skill trigger on at least 90% of should-trigger queries?
2. Does it NOT trigger on at least 95% of should-not-trigger queries?
3. Does the subagent produce correct output on all test scenarios?
4. Is every file under 100 lines?
5. Is the SKILL.md body under 5,000 tokens?
6. Does the description start with an action verb (third person)?
7. Are reference files loaded only when needed, not on every invocation?
8. Does the skill work after compaction (first 5K tokens retained)?

## Testing different skill types

**Reference skills**: Verify that the agent applies the conventions correctly.
Create a scenario where the agent would violate the convention without the skill.

**Task skills**: Verify that the agent follows the steps in order and produces
the expected output format.

**Hybrid skills**: Test both. Convention adherence and task completion.

## What to do when a test fails

Do not add more instructions. First diagnose why the agent failed:

Was the instruction unclear? Rewrite it.
Was the instruction missing? Add it, but keep it short.
Was the instruction contradicted by another instruction? Remove the conflict.
Was the instruction buried in a wall of text? Move it earlier or give it a header.

Re-run the failing test. If it passes, re-run all tests to check for regressions.
