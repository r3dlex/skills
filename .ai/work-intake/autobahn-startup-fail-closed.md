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
Public regression seam: proposed strict-TS `04-validate-handoff/autobahn/engine-pick.ts`, compiled to `ts-tooling/dist/04-validate-handoff/autobahn/engine-pick.js`, with identical command/exit/stdout behavior. The old engine-pick.sh seam is historical/intermediate only; separately qualified A5/E6 build/discovery/consumer transition must precede final activation. New source and command are proposed, never assumed base-present.
Coverage is unmeasured; characterize this narrow CLI seam before production edits.

1. Observe a regression against the unchanged helper for missing option values.
   Reject them promptly with exit 2 and no engine on stdout, then rerun it green.
2. Observe a regression for non-object or malformed goal JSON; reject it with exit
   2 and no engine, then rerun the same check green. A supplied invalid goal must
   not become valid merely because an engine override is also supplied.
3. Preserve valid signal precedence and valid overrides. Run targeted regressions,
   strict tsc/A5 complexity/cognitive/no-floating-promises checks and all ported TS repository lint/catalog/parity suites. The bound TSF-01..08 contract also requires approved inventory and Python-unavailable isolated build/full tests/local AND hosted exact-head CI/package/install/supported-host smoke, no fallback and failing planted-file/interpreter/package controls. Preserve immutable receipts and governed consumer retirement; no shell/Python final logic or self-admitting bootstrap.
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

## TypeScript requirement binding

- Preparation: `r3dlex/ai-tool-workspace:.omc/handoffs/ach-20261004/artifacts/consolidation-20261005/typescript-only-plan-alignment-20261008/FINAL-STATE.md` — 6603 bytes; SHA256 `3ec2814054f690631a8145ff9f6baebbf8c4c2a354c507be2ddfa3043af453e2`.
- Proposed canonical home: `r3dlex/ai-tool-workspace:docs/specifications/ACTIVE/typescript-only-final-state.md`. Adoption is pending. Canonical publication must bind its actual reviewed revision or retain this unresolved adoption dependency.
- Historical observations retain their original epoch. Proposed TypeScript sources and commands require their separately governed introducing deliveries; this working-plan correction supplies no implementation admission.
