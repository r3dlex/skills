#!/usr/bin/env python3
"""Shared traceability graph schema validator (offline, deterministic).

Single source of truth for the schema-1.1 contract documented in
``03-configure-generate/ai-catapult-init/modules/traceability.md``. Both the shipped final-package
validator (``scripts/validate-final-package.py``) and the in-test reference
validator (``tests/traceability-schema-v11_test.sh``) call into this module so
the doc, the runtime check, and the tests cannot drift.

Rules enforced (mirroring modules/traceability.md "Required validation"):
- ``schema_version`` is present and accepted (v1.0 AND any >= 1.1).
- Every node ``type`` is in the known enum for the declared schema version;
  v1.1 additively adds ``eval-result`` and ``trajectory-trace``. An unknown
  type fails at any version.
- Every node carries ``id``, ``type``, ``title``, ``status``, ``repo_id`` and
  either ``path`` or ``host_url``.
- Every node backlink references another existing node ID.
- Every edge ``source``/``target`` references an existing node ID.

No network or model access. Raises ``ValueError`` on any violation.
"""
from __future__ import annotations

# --- The schema-1.1 type enum (additive over v1.0) ---------------------------
V10_TYPES = {
    "brd", "prd", "adr", "plan", "issue", "pr",
    "test", "handoff", "workflow", "validation",
}
V11_ADDED_TYPES = {"eval-result", "trajectory-trace"}
KNOWN_TYPES = V10_TYPES | V11_ADDED_TYPES


def parse_version(value: str) -> tuple[int, ...]:
    return tuple(int(part) for part in str(value).split("."))


def validate_graph(graph: dict) -> None:
    """Validate a traceability graph dict against the 1.1 schema contract.

    Accepts schema_version >= 1.0 (back-compat) and treats the v1.1 node types
    as known. Raises ``ValueError`` on the first violation found.
    """
    if "schema_version" not in graph:
        raise ValueError("graph missing schema_version")
    version = parse_version(graph["schema_version"])
    if version < (1, 0):
        raise ValueError(f"unsupported schema_version {graph['schema_version']}")

    nodes: dict = {}
    for node in graph.get("nodes", []):
        if not isinstance(node, dict):
            raise ValueError(f"node is not an object: {node!r}")
        node_id = node.get("id")
        if not node_id:
            raise ValueError("node missing id")
        if node_id in nodes:
            raise ValueError(f"duplicate node id {node_id!r}")
        nodes[node_id] = node
    for node in nodes.values():
        node_type = node.get("type")
        if node_type not in KNOWN_TYPES:
            raise ValueError(f"unknown node type {node_type!r}")
        if not node.get("title"):
            raise ValueError(f"node {node['id']} missing title")
        if not node.get("status"):
            raise ValueError(f"node {node['id']} missing status")
        if not node.get("repo_id"):
            raise ValueError(f"node {node['id']} missing repo_id")
        if not (node.get("path") or node.get("host_url")):
            raise ValueError(f"node {node['id']} missing path/host_url")
        for backlink in node.get("backlinks", []):
            if backlink not in nodes:
                raise ValueError(f"dangling backlink {backlink}")
    for edge in graph.get("edges", []):
        if edge.get("source") not in nodes:
            raise ValueError(f"dangling edge source {edge}")
        if edge.get("target") not in nodes:
            raise ValueError(f"dangling edge target {edge}")
