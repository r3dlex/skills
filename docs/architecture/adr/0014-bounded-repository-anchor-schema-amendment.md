# ADR 0014: Bounded repository anchors in traceability graphs

## Status
Proposed.

## Context
Traceability schema `1.1` currently defines a strict node-type enum that adds `eval-result` and `trajectory-trace` to the `1.0` types. Unknown node types fail validation.

A brownfield Northstar handoff may encounter a graph that records its owning repository as a node. The handoff repair must be able to validate that node while deriving repository identity from existing traceability and workflow records. The node is informational; it must not imply that execution, deployment, authentication, payment, host mutation, or merge is authorized.

Adding `repo` to the strict `1.1` enum changes the meaning of an already published schema version. Updated consumers can still read existing `1.0` and `1.1` graphs, but an older strict `1.1` validator will reject a `1.1` graph containing `repo`. The repository does not currently state whether schema-version definitions are immutable. This ADR therefore records the same-version amendment and its compatibility debt explicitly rather than presenting it as transparent compatibility.

## Decision
Amend the traceability `1.1` validator contract in place to recognize `repo` as a third additive node type, subject to all of these constraints:

- `id` is exactly `repo:<repo_id>`.
- `repo_id` is a non-empty identifier containing only ASCII letters, digits, `.`, `_`, or `-`.
- `path` is exactly `.` and `status` is exactly `active`.
- Required fields remain `id`, `type`, `title`, `status`, `repo_id`, and `path`.
- The only optional fields are a non-empty string `label` and a list of string `backlinks`; every backlink resolves to an existing node.
- `host_url`, authority flags, and all other extension fields are rejected.
- The node records repository identity only. It grants no host, runtime, execution, deployment, authentication, payment, approval, or merge authority.
- `repo` remains invalid in schema `1.0`.

The anchor is optional. Existing fixtures, frozen graphs, review evidence, and user-authored nodes and edges are not rewritten merely to add it.

Ship the contract as one reviewed consumer unit: schema documentation, shared validator, Northstar handoff consumer, validation documentation, and positive and negative regression tests. Do not publish a graph that depends on `repo` before its consuming validators are updated.

## Compatibility declaration
This proposal preserves backward compatibility for updated consumers: they continue to accept unchanged `1.0` graphs and existing `1.1` graphs.

It does **not** promise forward compatibility with older strict consumers. An older validator that rejects `repo` is behaving according to its original enum, not proving that the graph is corrupt. Producers must not assume that labelling the graph `1.1` makes it readable by every historical `1.1` consumer.

## Alternatives
- **Publish schema `1.2`** — rejected for this bounded repair. A new version would signal the enum expansion more clearly, but it would expand the migration and fixture surface without making the graph readable by old strict validators, which reject the unknown type regardless. The in-place amendment instead carries an explicit compatibility warning and ships all repaired consumers together.
- **Encode repository identity as an existing node type** — rejected. A `workflow`, `validation`, or other artifact node would misstate the domain meaning.
- **Add host or authorization metadata to the anchor** — rejected. Repository identity is not authority.
- **Rewrite all existing graphs and fixtures** — rejected. The anchor is optional, and rewriting frozen evidence would destroy provenance without improving validation.
- **Let consumers ignore unknown node types** — rejected. It weakens the existing fail-closed traceability contract.

## Consequences
- Brownfield handoff tooling can validate a narrowly shaped repository identity node without inferring authority.
- Updated validators remain able to consume existing graphs unchanged.
- A same-version amendment requires a release note and coordinated consumer update because old strict validators will reject the new node.
- Frozen artifacts remain byte-preserved unless a separately reviewed migration explicitly changes them.

## Compliance
Verify the accepted choice with all of the following:

- Shared and consumer validators accept a valid repository-identity node in schema `1.1` or later and reject it in `1.0`.
- Tests reject unsafe IDs, mismatched IDs, non-root paths, non-`active` status, invalid labels or backlinks, `host_url`, unexpected fields, and authority-bearing fields.
- Existing `1.0` and `1.1` fixtures remain valid and unchanged.
- Northstar handoff tests prove repository-identity reconciliation without promoting blocked state or granting authority.
- Documentation states the old-consumer compatibility boundary and the absence of host, runtime, payment, or merge authority.
