# Autobahn Lint Gate

Read before committing a goal. autobahn had no lint awareness at all: it could
commit, pass review and merge while the repo's own pre-commit policy would have
rejected the diff. The reviewer then spends attention on what a linter would
have caught for free.

`lint-gate.sh` attaches to the commit seam in
[commit-protocol.md](commit-protocol.md), before the PR is opened.

## Detection

Most specific first; the first match wins and the rest are not consulted.

| Found at repo root | Runs |
| --- | --- |
| `prek.toml` | `prek run --all-files` |
| `.pre-commit-config.yaml` | `pre-commit run --all-files` |
| `package.json` with `scripts.lint` | `npm run lint` |

`prek.toml` beats `.pre-commit-config.yaml` because prek is the configured
runner where both exist; running both reports one policy twice.

## The three outcomes

- **Clean** — exit 0. Proceed to commit.
- **Failures** — exit 1. Blocking. Fix the diff; do not commit past it, and do
  not disable the rule to get green unless the goal is about that rule.
- **No policy configured** — exit 0, reported as `policy=none`. A repo without a
  lint policy has not failed lint. Blocking here would make the gate unusable in
  exactly the repos that most need the rest of autobahn.

## The case worth stating

A repo that **declares** a policy whose tool is **not installed** blocks.

Nothing linted the diff, so the gate has nothing to report but its own
ignorance. An uninstalled linter looks identical to a passing one unless you
check for it, and "the tool was missing" is not a reason to call a diff clean —
it is a reason to stop and install it.

The same reasoning covers a malformed `package.json`: it may well declare a lint
script, and the gate cannot tell, so it cannot pass.

## Safety rules

- Never commit past a failing lint policy.
- Never treat a missing linter, or an unreadable manifest, as a clean result.
- Never suppress a rule to reach green unless the goal is that rule.
