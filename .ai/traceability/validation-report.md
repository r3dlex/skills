# Discovery publication — narrow graph validation

**PASS for the additive metadata checks below**, observed `2026-10-06T06:32:32.862026Z`, actual command exit **0**. Not whole-graph schema approval, product TDD, CI, admission, certification or merge authority.

Base: `6b1e893238a64e8db933755ed1f954858c7c6eea`. Subject: `ach-skills-gate-discovery-repair / ACH-GW-DISC-01`; actual locally emitted generation `2a5d7d0b8bb081e788961c4e049e6dc249c02bc66772229a5c0fa6c0e99fd449`.

| Bound input | Raw SHA256 |
|---|---|
| Base live graph | `38e2f39d5d0d97118b118294e1d1ef1dff4d91e5fb8450845b3cc8942f4fa57c` |
| Candidate live graph | `37f75e8f7b969d8a467bb71ed7f78513c5676c68e96f9ef58a58f784173d1cf6` |
| Canonical generation graph | `1301065bbd0070fcde4628f83eeb26602313c435872bbf7b40200ca5b2c81d30` |
| Unchanged `scripts/traceability_schema.py` | `df053294f4adb31b8ab8f169df67bc7cc008d32861a7f8a7c7af3186baca7379` |

Native read-only Python invoked the existing `traceability_schema.validate_graph` on the **two appended nodes and one appended edge**, with schema `1.1`; it passed. Standard-library comparisons additionally checked:

- All 47 base nodes, 42 base edges and every other graph field remain unchanged and ordered as prefixes. Candidate totals: 49 nodes, 43 edges.
- All global node IDs are unique; every global edge endpoint and backlink resolves. The new pair has mutual backlinks and real, non-symlink artifact paths.
- New IDs and edge match the producer's canonical generation graph exactly; goal revision remains `8520938fdbb044f3bfc0daa4cedbf97fe650a66a988cff8f82d99910dbd543f7`.
- Registered bundle/graph/handoff digests and the unique bound specification digest match actual files.

The first narrow check exited **1** at the append-prefix assertion because the initial patch inserted this lane's new nodes before an older generation. Only the two new nodes were moved to the end; the identical command then exited **0**. No old node, validator, test or assertion was edited. This metadata check is not product red/green evidence.

**Limits:** the base already contains `spec` nodes outside the shared schema validator's type enum. That pre-existing mismatch is preserved; the helper was not run as a whole-graph schema/CI check, modified or told to permit that type. This report verifies only its stated additive schema, global references, preserved history and artifact bindings. The registry remains the sole v2 completion pointer; this supplemental graph/report grants nothing.

The v2 producer itself emits only four generation files and the registration (`observer.py:1156–1168,1198–1221`). This live graph/report is separately patched metadata under `DISCOVERY-METADATA-20261006`, not falsely attributed to the producer. Its real planning receipt reports blocking **0**, approval **5**, deferred **5**, `planning_complete: true` and authority **none**; approval, current live product authority, implementation and merge remain separate.
