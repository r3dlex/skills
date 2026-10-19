"""Derive the refusal inventory from the anchored source, never from test names."""
import ast


def prefix(node):
    if isinstance(node, ast.Constant) and isinstance(node.value, str): return node.value.split(':', 1)[0]
    if isinstance(node, ast.BinOp): return prefix(node.left)
    return None


def report(parity, lib):
    targets = set()
    for path in [lib / 'readiness_contract.py', lib / 'verification.py']:
        tree = ast.parse(path.read_text())
        for node in ast.walk(tree):
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in ('require', 'stop'):
                targets.add((path.name, node.lineno))
    reached = targets & parity.REFUSAL_SITES
    missing = sorted(targets - reached)
    messages = {message.split(':', 1)[0] for message in parity.REFUSALS}
    return {'target_refusal_sites': len(targets), 'reached_refusal_sites': len(reached), 'missing_refusal_sites': missing,
            'observed_refusal_prefixes': sorted(messages), 'gate_status_unknown_runtime': ('readiness_contract.py', 785) in parity.LINES}
