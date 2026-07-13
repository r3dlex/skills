# DPUA CI adapter contract

Read when generating CI for an umbrella execution profile. The execution
profile is the provider-neutral policy; provider YAML is a selected-host
projection, never a second policy authority.

## Generation contract

- Render only hosts listed by `settings.host_selection`: GitHub Actions,
  Azure Pipelines, or GitLab CI. Epic Lore/Horde is reserved and rejected.
- Default to `runner_preference: self-hosted`. A repository may explicitly
  override the preference to `hosted` without changing host selection.
- Automatic hosted fallback is pre-dispatch, waits for the configured queue
  threshold, and starts exactly one workload. `max_redispatch_count` is zero.
- `release`, `publish`, `deployment`, and `cas-write` are never eligible for
  hosted fallback or hosted preference.
- Retry only the classified transient classes in `transient_retry.classes`,
  at most once, on the executor selected before the first workload attempt.
  Deterministic failures and request-only cross-host replay are outside this
  adapter retry path.
- ADO selects one conditional pool job. GitLab dispatches one child pipeline
  whose variable selects one tagged workload. Selector failure fails closed.
- Adapter status is `supported` only after disposable-host smoke and readback.
  Structural/golden proof alone leaves the adapter `experimental` or `blocked`.

Run `python3 scripts/render-ci-adapters.py --profile <profile> --output <dir>`.
Use `--check` in CI to fail on projection drift without modifying files.
