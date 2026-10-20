# e6-d13-cc fixtures (synthetic)

Every artifact under this directory is **synthetic test data** built by
`build.mjs` at test time. Nothing here is a real D13 capture, a real driver
invocation, a real approval, a real export, a real certificate or real capture
authenticity.

- `build.mjs` materializes four temporary Git target repositories, a reference
  driver clone, a candidate driver clone or linked worktree, a retained run
  directory and (for consumer cases) a temporary consumer repository.
- `cases.mjs` is the case table `P1`, `M01`-`M34`, `O01`-`O09`, `C01`-`C15`
  with each case's required assertion and exit code.
- `verify.mjs` asserts the tool's actual output against that table.

The Git observations recorded in synthetic runs are produced by running the
same bounded read-only Git commands the checker uses. They prove checker
behaviour only. They do not authenticate any real collection, custody, hosted
completion or live remote freshness; the checker always reports
`capture_authenticity: unverified` and `live_remote_freshness: unverified`.