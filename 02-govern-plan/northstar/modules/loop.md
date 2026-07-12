# Northstar Interview Loop

Read when running the intake loop. `northstar` delegates the whole loop to
existing skills and only enforces the **both-satisfied** gate; it reimplements
neither the deep-interview question loop nor the grill-me decision tree.

## Roles

- **Primary — `deep-interview`.** Drives one question at a time until measured
  ambiguity is at or below its threshold. This is the mandatory leg.
- **Adversarial / skippable — `grill-me`.** An optional stress pass the user may
  decline. Skipping it bypasses only the adversarial pass — the issue is still
  raised afterward.

## The "both satisfied" rule

The loop is complete when **both** are true:

1. the `deep-interview` ambiguity gate is met, AND
2. the `grill-me` decision tree is clear **OR** grill-me was explicitly skipped.

If the user has not chosen whether to run grill-me, offer it:

<!-- codex:optional -->
Ask the user (interactive) whether to run the adversarial grill-me pass.
Fallback (Codex / plain markdown): present two options as a numbered list — `1`
run grill-me, `2` skip — and ask the user to reply with a number.

## Safety rules

- Do not declare the loop done on the deep-interview gate alone unless grill-me
  was explicitly skipped.
- Do not reimplement either skill's loop; record only their outcome.
