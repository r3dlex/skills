# Validation Module

Read when proving the scaffold matches the repository baseline.

## Commands

Run from `skills/` when validating this repository:

```sh
tests/test-skills.sh
tests/test-scripts.sh
tests/run-tests.sh
bash scripts/archgate.sh --mode structural --rules .rules.ts --format json
./scripts/verify-golden-dir.sh . reference/golden-root
./scripts/verify-golden-dir.sh . reference/golden-skills
```

## Expected interpretation

- `tests/test-skills.sh` is authoritative only after its frontmatter-aware body-line parser passes focused regression fixtures.
- Corrected line-count failures identify progressive-disclosure cleanup targets; do not hide them by weakening the validator.
- Golden verification compares scaffolded files and marker presence; `upstream.lock` SHA content is intentionally structure-checked, not byte-compared.
