# e6-d13-cc fixtures (synthetic)

Every artifact under this directory is **synthetic test data** built by
`build.mjs` at test time. Nothing here is a real D13 capture, a real driver
invocation, a real approval, a real export, a real certificate or real capture
authenticity.

- `build.mjs` materializes four temporary Git target repositories, a reference
  driver clone, a candidate driver clone or linked worktree, a retained run
  directory and (for consumer cases) a temporary consumer repository.
- `lib/cases.mjs` retains all 59 contract cases (`P1`, `M01`–`M34`,
  `O01`–`O09`, `C01`–`C15`) and adds 64 cure regressions (`R01`–`R34`,
  `D01`–`D30`): 123 named cases. C07 runs five distinct report mutations;
  C08 runs nine stream/metadata/snapshot mutations with exact exits and a
  mandatory `raw-inputs-bound` failure. Named failures cannot substitute for
  each other.
- `verify.mjs` asserts the tool's actual output against that table.
- Consumer positives use a connected publication → distinct supplier PR head →
  two-parent merge → actual candidate capture → evidence-only HEAD history,
  copied immutable registration inputs, and full driver inventories. C13 moves
  the whole clean consumer checkout and makes both archived driver roots
  unavailable. C15 exercises the real Bash suite's present/absent consumer loop.
- O07 moves an actual temporary ref while recording observations. R21 and
  D23/D24 move real temporary refs between the checker's start/finish reads;
  their wrapper forwards actual Git responses and records the mutation.
- `verifier-test.mjs` proves empty/null stdout cannot pass on exit code alone.
- D29 rejects a message-only fabricated merge parent; D30 accepts a real
  two-parent merge even when its message repeats a `parent ...` line. Only the
  consecutive structural parent headers immediately after `tree` are parsed.

Base Git observations are produced by the same bounded read-only commands the
checker uses; negative fixtures deliberately mutate metadata/responses/bytes.
They prove checker
behaviour only. They do not authenticate any real collection, custody, hosted
completion or live remote freshness; the checker always reports
`capture_authenticity: unverified` and `live_remote_freshness: unverified`.
