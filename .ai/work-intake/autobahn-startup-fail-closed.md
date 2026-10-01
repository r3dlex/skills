---
name: autobahn-startup-fail-closed
status: in-progress
---

# Autobahn startup input repair

User request: fix Autobahn and start the exact Northstar small-work handoff.
This independently requested helper repair is not implementation of the blocked
`SWP-ROOT-01` root-adoption goal or its child packages.

## Bounded repair plan

Base: latest `skills/main` at `dad05ec6f541f88b2240a4df98cd98deaf7e26e5`.
Use an isolated worktree; preserve existing checkouts and reference-only sources.
Public regression seam: `autobahn/engine-pick.sh` command, exit status and stdout.
Coverage is unmeasured; characterize this narrow CLI seam before production edits.

1. Observe a regression against the unchanged helper for missing option values.
   Reject them promptly with exit 2 and no engine on stdout, then rerun it green.
2. Observe a regression for non-object or malformed goal JSON; reject it with exit
   2 and no engine, then rerun the same check green. A supplied invalid goal must
   not become valid merely because an engine override is also supplied.
3. Preserve valid signal precedence and valid overrides. Run targeted regressions,
   shell syntax checks, existing repository lint and catalog/parity checks.
4. Independently review the final diff. Validate source-to-flat packaging using an
   isolated builder; do not forge the existing source lock or edit installed cache.
5. Retry exact small-work admission, without changing the immutable handoff or
   inventing readiness context, owner, TDD provenance or live authority.

## Explicit exclusions and remaining dependencies

- No readiness-policy waiver, fake context, trust-anchor rewrite or merge bypass.
- No model inference/download, provider change, reference-framework edit or new
  dependency. No work on foreign branches.
- Legacy `ralph`/`ultrawork` routing requires a separate host-capability contract;
  globally renaming engines would break cross-harness behavior or nest goal owners.
- `SWP-ROOT-01` remains blocked until its repo-owned prerequisite deliveries and
  independent admission/authority exist. This helper repair cannot supply them.
- Isolated packaging evidence is not a release, installed activation or dispatch.

No three-attempt history was found for this new helper-input repair. Prior
small-work read-only admission failures are not execution attempts or authority.

## Narrow delivery backport

The parent evidence records the original latest-main repair. For packaging,
backport that repair onto the existing ai-catapult pin
`b87fdc2029dad16389cf2501e0faf7934b33b71c`, rather than importing unrelated
changes to skill invocation and upstream-lock staleness policy. The immutable
source fix remains on its own current-main PR.

[`backport/evidence.json`](../evidence/autobahn-startup-fail-closed/backport/evidence.json)
records genuine pinned-before-state RED and backported GREEN from the unchanged
public regression test. Source helper bytes match the original repair.
This branch is a reviewed delivery pin, not a merge proposal that reverts main.
Readiness, engine capability changes and model/runtime ownership remain separate.
