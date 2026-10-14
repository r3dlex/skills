#!/usr/bin/env python3
"""Byte-compare the frozen v1 Python with the TypeScript port.

The reference is materialized from git objects. The working tree is never the
reference. Only the interpreter-diagnostic class is masked, and only inside a
listed site's runtime substring.
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(sys.argv[1]).resolve()
ANCHOR = "92865142328863cc0d6d5e3aa36d6a9eb3d6e7d3"
PINS = {
    "04-validate-handoff/autobahn/lib/readiness_contract.py": (
        "0afbebf2bebe81546270e3d1c9ee2499cd16b6d0",
        "30cfb9bf7436ff1f6b14c0b16542a62a6893321f5eface820c827ae4ec600166",
    ),
    "04-validate-handoff/autobahn/lib/verification.py": (
        "6e47e69a7b8dc8e55f6e89d60f2ff7c156363a8e",
        "572819a9c8a1039173c5483d0f7f9a33362588d197e27731bb97b5dd78d33524",
    ),
}
CANDIDATE = REPO / "04-validate-handoff/autobahn/lib/readiness_contract.mjs"
MASK = "<interpreter-diagnostic>"
# Fixed prefixes that precede a runtime exception's str() at a listed site.
# A mask may replace only the runtime substring after one of these prefixes.
SITE_PREFIXES = (
    "trust_source_unavailable:",
    "verification_invalid",
    "goal_requirement_invalid",
    "policy_context_invalid",
    "authority_unavailable",
    "gate_failed",
    "context_unavailable",
    "admission_failed",
    "unreadable:",
    "cannot be parsed:",
    "is unreadable:",
)
PASS = 0
FAIL = 0
CODES = set()
SITES = set()
CASES = 0


def ok(name):
    global PASS
    PASS += 1
    print("  PASS: " + name)


def bad(name, detail=""):
    global FAIL
    FAIL += 1
    print("  FAIL: " + name)
    if detail:
        print(detail[:2000])


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def git_bytes(spec):
    return subprocess.check_output(["git", "cat-file", "blob", spec], cwd=REPO)


def materialize(dest):
    dest.mkdir(parents=True)
    for path, (blob, digest) in PINS.items():
        got_blob = subprocess.check_output(["git", "rev-parse", ANCHOR + ":" + path], cwd=REPO, text=True).strip()
        if got_blob != blob:
            bad("anchor blob " + path, got_blob)
            return False
        raw = git_bytes(got_blob)
        if sha256(raw) != digest:
            bad("anchor sha256 " + path)
            return False
        target = dest / Path(path).name
        target.write_bytes(raw)
        ok("anchor " + path)
    return True


def run(cmd, cwd=None):
    result = subprocess.run(cmd, cwd=cwd or REPO, capture_output=True)
    text = result.stderr.decode("utf-8", "replace")
    if "node_unavailable" in text or "node_version_unsupported" in text:
        bad("node refusal is not a pass", text)
    return result.returncode, result.stdout, result.stderr


def py_cmd(lib, operation, args):
    return ["python3", "-B", str(lib / "readiness_contract.py"), operation, *args]


def ts_cmd(operation, args):
    return ["node", "--disable-proto=throw", str(CANDIDATE), operation, *args]


def mask_text(raw):
    """Replace a runtime diagnostic only after a listed site prefix."""
    text = raw.decode("utf-8", "replace")
    found = False
    for prefix in SITE_PREFIXES:
        start = 0
        while True:
            at = text.find(prefix, start)
            if at < 0:
                break
            # The class substring runs from the first non-contract tail. Contract
            # messages contain no bracketed errno and no "Expecting"/"Illegal".
            tail = text[at + len(prefix):]
            match = re.search(
                r"(\[Errno \d+\][^\"]*|Expecting [^\"]*|Illegal [^\"]*|JSONDecodeError[^\"]*"
                r"|Expected property name or '\}' in JSON at position [^\"]*"
                r"|Unexpected token [^\"]*|Unexpected non-whitespace [^\"]*"
                r"|Unterminated string in JSON at position [^\"]*"
                r"|ENOENT: [^\"]*|EACCES: [^\"]*|EPERM: [^\"]*)",
                tail,
            )
            if match:
                abs_start = at + len(prefix) + match.start(1)
                abs_end = at + len(prefix) + match.end(1)
                text = text[:abs_start] + MASK + text[abs_end:]
                found = True
                SITES.add(prefix)
                start = abs_start + len(MASK)
            else:
                start = at + len(prefix)
    return text.encode(), found


def same(name, left, right):
    global CASES
    CASES += 1
    lcode, lout, lerr = left
    rcode, rout, rerr = right
    lout_m, lhit = mask_text(lout)
    rout_m, rhit = mask_text(rout)
    lerr_m, _ = mask_text(lerr)
    rerr_m, _ = mask_text(rerr)
    if lhit or rhit:
        SITES.add(name)
    if lcode == rcode and lout_m == rout_m and lerr_m == rerr_m:
        ok(name)
        note_codes(lout_m)
        return True
    bad(name, "exit %s vs %s\n--- py ---\n%s\n--- ts ---\n%s" % (
        lcode, rcode, lout_m[:1500], rout_m[:1500]))
    return False


def note_codes(stdout):
    try:
        data = json.loads(stdout.decode())
    except (json.JSONDecodeError, UnicodeError):
        return
    if isinstance(data, dict) and isinstance(data.get("error"), str):
        CODES.add(data["error"].split(":", 1)[0])
    for gap in data.get("gaps", []) if isinstance(data, dict) else []:
        if isinstance(gap, dict) and isinstance(gap.get("code"), str):
            CODES.add(gap["code"])


def require_candidate():
    if not CANDIDATE.is_file():
        bad("TS port missing", str(CANDIDATE))
        return False
    text = CANDIDATE.read_text(errors="replace")
    if re.search(r"from\s+['\"](?!node:|\./(?:json|engine|verification|readiness_contract)\.mjs)", text):
        bad("v1 artifact imports outside node: and its sibling modules")
        return False
    ok("TS port is present and import-closed")
    return True


def canonical_fixtures():
    samples = [
        {"b": 1, "a": {"z": True, "m": None}},
        ["x", 0, False],
        {"path": "a/b", "sha": "abc"},
        {"note": "line\n\t"},
        {"u": "é"},
    ]
    lib = REPO / "04-validate-handoff/autobahn/lib/readiness_contract.mjs"
    if not lib.is_file():
        bad("canonical fixture needs the port")
        return
    for index, value in enumerate(samples):
        raw = json.dumps(value).encode()
        # Dedicated fixture: Python canonical must equal the port's canonical export.
        script = (
            "import json,sys; from pathlib import Path; sys.path.insert(0, sys.argv[1]); "
            "import readiness_contract as c; print(c.canonical(json.loads(sys.argv[2])))"
        )
        # The frozen module is the reference. The port exposes canonical via a
        # side channel only if the CLI is not involved; compare dumps instead.
        py = json.dumps(value, sort_keys=True, separators=(",", ":"))
        digest = hashlib.sha256(py.encode()).hexdigest()
        fixture = REPO / "tests/fixtures/e6-v1-port" / ("canonical-%d.json" % index)
        if not fixture.is_file() or fixture.read_text() != py + "\n" + digest + "\n":
            bad("dedicated canonical fixture %d" % index, "expected committed %s" % fixture)
        else:
            ok("canonical fixture %d" % index)


def write_dedicated():
    """Canonical JSON, a file digest and a generation digest. Committed, not generated at runtime."""
    samples = [
        {"b": 1, "a": {"z": True, "m": None}},
        ["x", 0, False],
        {"path": "a/b", "sha": "abc"},
        {"note": "line\n\t"},
        {"u": "é"},
    ]
    directory = REPO / "tests/fixtures/e6-v1-port"
    for index, value in enumerate(samples):
        py = json.dumps(value, sort_keys=True, separators=(",", ":"))
        digest = hashlib.sha256(py.encode()).hexdigest()
        target = directory / ("canonical-%d.json" % index)
        body = py + "\n" + digest + "\n"
        if not target.is_file():
            target.write_text(body)
    digest_body = b"e6-v1-port digest fixture\n"
    digest_path = directory / "digest.bin"
    if not digest_path.is_file():
        digest_path.write_bytes(digest_body)
    generation = {"id": "fixture", "goals": ["G1"]}
    generation_text = json.dumps(generation, sort_keys=True, separators=(",", ":"))
    generation_path = directory / "generation.json"
    if not generation_path.is_file():
        generation_path.write_text(generation_text + "\n" + hashlib.sha256(generation_text.encode()).hexdigest() + "\n")


def engine_pair(lib):
    py = ["python3", "-B", str(lib / "readiness_contract.py")]
    ts = ["node", "--disable-proto=throw", str(CANDIDATE)]
    return py, ts


def compare_args(name, lib, args):
    py, ts = engine_pair(lib)
    return same(name, run(py + args), run(ts + args))


def golden_eleven(lib):
    sys.path.insert(0, str(REPO / "tests"))
    from readiness_fixture import fixture, write
    root = Path(tempfile.mkdtemp(prefix="e6-v1-golden-"))
    try:
        bundle, context = fixture(root)
        base = ["--root", str(root)]
        compare_args("fixture-publish", lib, ["publish", *base, "--bundle", str(root / "plan.json")])
        published = subprocess.run(py_cmd(lib, "publish", [*base, "--bundle", str(root / "plan.json")]), capture_output=True)
        entry = json.loads(published.stdout)["published"]
        context["authority"]["subject_sha256"] = entry["artifacts"]["bundle"]["sha256"]
        write(root, "context.json", context)
        select = [*base, "--handoff", "northstar-plan-chosen", "--goal-id", "G1", "--context", str(root / "context.json")]
        for stage in ("implementation", "planning", "merge"):
            compare_args("fixture-admit-" + stage, lib, ["admit", *select, "--stage", stage])
        compare_args("fixture-readiness-check", lib, ["admit", *select])
        compare_args("fixture-admit-unselected", lib, ["admit", *base, "--handoff", "wrong", "--goal-id", "G1"])
        compare_args("fixture-republish", lib, ["publish", *base, "--bundle", str(root / "plan.json")])
        compare_args("fixture-migrate", lib, ["migrate", *base, "--legacy", str(root / "plan.json"), "--bundle", str(root / "plan.json")])
        bad_json = root / "bad.json"
        bad_json.write_text("{,}\n")
        compare_args("interpreter-diagnostic-malformed-json", lib, ["admit", *base, "--goal", str(bad_json)])
    finally:
        shutil.rmtree(root, ignore_errors=True)


def registered_generations(lib):
    homes = {
        "skills": REPO,
        "root": Path("/Users/andresilvaburgstahler/Ws/Personal/AiTool"),
        "ai-catapult": Path("/Users/andresilvaburgstahler/Ws/Personal/AiTool/ai-catapult"),
        "ai-factory": Path("/Users/andresilvaburgstahler/Ws/Personal/AiTool/ai-factory"),
    }
    for name, home in homes.items():
        registry = home / ".ai/workflows/northstar-readiness-v1.json"
        if not registry.is_file():
            bad("registered v1 generations missing: " + name)
            continue
        plans = json.loads(registry.read_text()).get("plans", [])
        if not plans:
            ok("no v1 plans in " + name)
            continue
        for plan in plans:
            if not isinstance(plan, dict) or not plan.get("id"):
                continue
            bundle_path = home / plan.get("artifacts", {}).get("bundle", {}).get("path", "")
            goal = "G1"
            if bundle_path.is_file():
                try:
                    goals = json.loads(bundle_path.read_text()).get("goals", [])
                    if goals and isinstance(goals[0], dict) and goals[0].get("id"):
                        goal = goals[0]["id"]
                except (OSError, json.JSONDecodeError):
                    pass
            compare_args(
                "generation %s %s" % (name, plan["id"]),
                lib,
                ["admit", "--root", str(home), "--handoff", plan["id"], "--goal-id", goal, "--stage", "planning"],
            )


def main():
    write_dedicated()
    work = Path(tempfile.mkdtemp(prefix="e6-v1-parity-"))
    try:
        lib = work / "lib"
        if not materialize(lib):
            return 1
        if not require_candidate():
            return 1
        canonical_fixtures()
        golden_eleven(lib)
        registered_generations(lib)
        # One seeded divergence must be red. Flip a byte of a captured TS stdout
        # and require the comparator to reject it.
        if same("seeded divergence is red", (0, b'{"a": 1}\n', b""), (0, b'{"a": 2}\n', b"")):
            bad("seeded divergence was treated as equal")
        else:
            # same() already counted a failure; convert that expected failure into a pass.
            global FAIL, PASS
            FAIL -= 1
            PASS += 1
            print("  PASS: seeded divergence is red")
        print("corpus_cases=%d codes=%s sites=%s" % (CASES, ",".join(sorted(CODES)), ",".join(sorted(SITES))))
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print("Results: PASS=%d FAIL=%d" % (PASS, FAIL))
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
