# Northstar Interview Loop

Read when running the intake loop. `northstar` delegates the whole loop to
existing skills and only enforces the **both-satisfied** gate; it reimplements
neither the deep-interview question loop nor the adversarial decision tree.

## Roles

- **Primary — `deep-interview`.** Drives one question at a time until measured
  ambiguity is at or below its threshold. This is the mandatory leg.
- **Adversarial / skippable — `grill-with-docs` then `grill-me`.** An optional
  stress pass the user may decline. Skipping it bypasses only the adversarial
  pass — the issue is still raised afterward.

The two adversarial skills are offered and declined **as a unit**, in that order.
`grill-with-docs` runs first because it is the grounded one: it tests the plan
against the repo's documented language, ADRs and `CONTEXT.md`, and settles
terminology. `grill-me` then attacks what survives, open-ended. Running the
open-ended pass first wastes it arguing about words the docs already define.

Offering them separately would be worse than offering neither: a user who
declines one and accepts the other leaves the gate below in a state northstar
cannot evaluate.

## The "both satisfied" rule

The loop is complete when **both** are true:

1. the `deep-interview` ambiguity gate is met, AND
2. the adversarial decision tree is clear **OR** the pass was explicitly skipped.

If the user has not chosen whether to run the adversarial pass, offer it:

<!-- codex:optional -->
Ask the user (interactive) whether to run the adversarial pass.
Fallback (Codex / plain markdown): present two options as a numbered list — `1`
run `grill-with-docs` then `grill-me`, `2` skip both — and ask the user to reply
with a number.

## Safety rules

- Do not declare the loop done on the deep-interview gate alone unless the
  adversarial pass was explicitly skipped.
- Do not offer or run the two adversarial skills independently of each other.
- Do not reimplement any skill's loop; record only their outcome.
