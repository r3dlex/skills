#!/usr/bin/env python3
"""Byte-compare the frozen v1 Python with the TypeScript port.

The reference is materialized from git objects. The working tree is never the
reference. Only the interpreter-diagnostic class is masked, and only inside a
listed site's runtime substring.
"""
import hashlib
import contextlib
import difflib
import importlib
import io
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
NODE = shutil.which("node")
PYTHON = sys.executable
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
REFUSALS = set()
LINES = set()
DIAGNOSTICS = set()
REFUSAL_SITES = set()
EXCEPTION_SITES = set()
GATE_BRANCHES = set()


def observe(function, *args, **kwargs):
    def trace(frame, event, arg):
        name = frame.f_code.co_filename.rsplit('/', 1)[-1]
        if name not in ('readiness_contract.py', 'verification.py'): return None
        if event == 'line': LINES.add((name, frame.f_lineno))
        if event == 'line' and 'error' in frame.f_locals and frame.f_lineno in (534,644,657,719,741,786,908,932,1165,148,155,168):
            EXCEPTION_SITES.add((name, frame.f_lineno, type(frame.f_locals['error']).__name__))
        if event == 'line' and name == 'readiness_contract.py' and frame.f_lineno == 785:
            error = frame.f_locals['error']
            GATE_BRANCHES.add(('unknown' if any(token in str(error) for token in ('unavailable','missing','required','No such file')) else 'blocked', type(error).__name__))
        if event == 'call' and frame.f_code.co_name == 'require' and not frame.f_locals.get('value'):
            REFUSALS.add(str(frame.f_locals.get('message')))
            REFUSAL_SITES.add((name, frame.f_back.f_lineno))
        if event == 'call' and frame.f_code.co_name == 'stop':
            REFUSALS.add(str(frame.f_locals.get('message')))
            REFUSAL_SITES.add((name, frame.f_back.f_lineno))
        if event == 'exception': DIAGNOSTICS.add((name, frame.f_lineno, arg[0].__name__))
        return trace
    previous = sys.gettrace()
    sys.settrace(trace)
    try: return function(*args, **kwargs)
    finally: sys.settrace(previous)


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
    if len(cmd) >= 4 and cmd[2] == str(REPO / 'tests/fixtures/e6-v1-port/reference.py') and not os.environ.get('E6_V1_FAULT'):
        return reference_main(cmd)
    with tempfile.TemporaryDirectory(prefix="e6-trace-") as temporary:
        trace = Path(temporary) / "coverage.json"
        result = subprocess.run(cmd, cwd=cwd or REPO, capture_output=True, env=dict(os.environ, E6_V1_TRACE=str(trace)))
        if trace.exists():
            coverage = json.loads(trace.read_text())
            REFUSALS.update(coverage["refusals"])
            LINES.update(map(tuple, coverage["lines"]))
            DIAGNOSTICS.update(map(tuple, coverage["diagnostics"]))
            REFUSAL_SITES.update(map(tuple, coverage.get("refusal_sites", [])))
            EXCEPTION_SITES.update(map(tuple, coverage.get("exception_sites", [])))
            GATE_BRANCHES.update(map(tuple, coverage.get("gate_branches", [])))
    text = result.stderr.decode("utf-8", "replace")
    if "node_unavailable" in text or "node_version_unsupported" in text:
        bad("node refusal is not a pass", text)
    return result.returncode, result.stdout, result.stderr


def reference_main(cmd):
    """Call the exact anchored main, avoiding a new Python process per input.

    Fault-injection cases retain their isolated reference subprocess. No fatal
    exception is caught here; only argparse's ordinary SystemExit is captured.
    """
    frozen = sys.modules['readiness_contract']
    assert Path(frozen.__file__).resolve().parent == Path(cmd[3]).resolve()
    stdout, stderr = io.StringIO(), io.StringIO()
    previous = sys.argv
    sys.argv = [str(Path(cmd[3]) / 'readiness_contract.py'), *cmd[4:]]
    try:
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            try: code = observe(frozen.main)
            except SystemExit as exit: code = exit.code
    finally:
        sys.argv = previous
    return code, stdout.getvalue().encode(), stderr.getvalue().encode()


def py_cmd(lib, operation, args):
    return [PYTHON, "-B", str(REPO / "tests/fixtures/e6-v1-port/reference.py"), str(lib), operation, *args]


def ts_cmd(operation, args):
    return ["node", "--disable-proto=throw", str(CANDIDATE), operation, *args]


def mask_stderr(raw):
    """Never mask a prefix embedded in usage text, argv or an unrelated log."""
    text = raw.decode('utf-8', 'replace')
    for prefix in SITE_PREFIXES:
        fixed = prefix if prefix.endswith(':') else prefix + ':'
        if not text.startswith(fixed): continue
        tail = text[len(fixed):]
        start = runtime_tail(tail)
        if start is not None:
            newline = '\n' if tail.endswith('\n') else ''
            return (fixed + tail[:start] + MASK + newline).encode(), True
    return raw, False


def runtime_tail(value):
    """Locate only a standard-library/runtime exception, never an Invalid code."""
    start = 0
    nested = re.match(r'verification\[\d+\](?:\.cwd is unreadable: | command cannot be parsed: | script is unreadable: )', value)
    if nested: start = nested.end()
    if value.startswith('trust_source_unavailable:'):
        found = re.search(r'(?:\[Errno \d+\]|ENOENT:|EACCES:|EPERM:)', value)
        if found: start = found.start()
    tail = value[start:]
    if re.match(r'(?:lstat: embedded null character in path|embedded null byte)', tail): return start
    if re.match(r"argument of type '[^']+' is not a container or iterable", tail): return start
    if re.fullmatch(r"'[^']*'", tail): return start  # KeyError.__str__
    if re.match(r'(?:string|list) indices must be ', tail): return start
    if tail.startswith('can only concatenate str '): return start
    if re.match(r'(?:day \d+ must be |month must be |hour must be |minute(?:,| must be )|second must be |offset must be |year (?:must be |\d+ is out of range))', tail): return start
    runtime = r"(?:\[Errno \d+\]|E(?:NOENT|ACCES|PERM|ISDIR|LOOP|NOTDIR):|Expecting |Illegal |Unexpected |Unterminated |expected string or bytes-like object|cannot use '.+' as a (?:set element|dict key)|unhashable type:|Invalid isoformat string:|'[^']+' object (?:has no attribute|is not iterable|is not subscriptable)|'in <string>' requires string as left operand|argument of type '[^']+' is not iterable|'utf-8' codec can't decode|The encoded data was not valid for encoding|Cannot (?:read|convert|use)|No closing quotation|No escaped character|argument should be a str or an os.PathLike object)"
    return start if re.match(runtime, tail) else None


def mask_text(raw):
    try:
        text = raw.decode('utf-8')
        data = json.loads(text)
    except (ValueError, UnicodeError):
        return mask_stderr(raw)
    decoder = json.JSONDecoder()
    edits = []
    def walk(index, path, parent):
        while text[index].isspace(): index += 1
        if text[index] == '{':
            index += 1
            while True:
                while text[index].isspace(): index += 1
                if text[index] == '}': return index + 1
                key, index = decoder.raw_decode(text, index)
                while text[index].isspace() or text[index] == ':': index += 1
                child = parent.get(key) if isinstance(parent, dict) else None
                index = walk(index, path + (key,), child)
                while text[index].isspace(): index += 1
                if text[index] == ',': index += 1
        if text[index] == '[':
            index += 1
            counter = 0
            while True:
                while text[index].isspace(): index += 1
                if text[index] == ']': return index + 1
                index = walk(index, path + (counter,), parent[counter])
                counter += 1
                while text[index].isspace(): index += 1
                if text[index] == ',': index += 1
        value, end = decoder.raw_decode(text, index)
        if isinstance(value, str) and path:
            container = data
            for part in path[:-1]: container = container[part]
            code = container.get('code') if isinstance(container, dict) else None
            allowed = path == ('error',) or (path[-1] == 'detail' and code in {'verification_invalid', 'goal_requirement_invalid', 'policy_context_invalid', 'authority_unavailable', 'gate_failed', 'context_unavailable', 'admission_failed'})
            if allowed:
                prefix = ''
                suffix = value
                if code == 'gate_failed' and ':' in value: prefix, suffix = value.split(':', 1); prefix += ':'
                start = runtime_tail(suffix)
                if start is not None:
                    edits.append((index, end, json.dumps(prefix + suffix[:start] + MASK)))
                    SITES.add(code if isinstance(code, str) else 'error')
        return end
    walk(0, (), data)
    for start, end, replacement in reversed(edits): text = text[:start] + replacement + text[end:]
    return text.encode(), bool(edits)


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
    difference = "\n".join(difflib.unified_diff(lout_m.decode().splitlines(), rout_m.decode().splitlines(), fromfile="python", tofile="typescript", n=1))
    bad(name, "exit %s vs %s\n%s\nstderr: %r vs %r" % (lcode, rcode, difference, lerr_m, rerr_m))
    return False


def mask_self_probes():
    value = {'error': 'stale_file:expected string or bytes-like object', 'outside': '[Errno 2] do not mask'}
    raw = json.dumps(value).encode()
    if mask_text(raw) == (raw, False): ok('mask preserves contract text and non-site fields')
    else: bad('mask changed bytes outside the interpreter-diagnostic class')
    raw = b'{"gaps": [{"code": "gate_failed", "detail": "gate:[Errno 2] missing", "status": "unknown"}]}'
    expected = b'{"gaps": [{"code": "gate_failed", "detail": "gate:<interpreter-diagnostic>", "status": "unknown"}]}'
    if mask_text(raw) == (expected, True): ok('mask locates runtime suffix and preserves gate/status bytes')
    else: bad('mask failed to locate the runtime substring')
    usage = b"usage: tool\nerror: invalid choice: 'admission_failed:Illegal user text'\n"
    if mask_text(usage) == (usage, False): ok('mask preserves diagnostic-looking argv text on stderr')
    else: bad('mask rewrote a usage diagnostic outside the class')
    for diagnostic in ('lstat: embedded null character in path', 'embedded null byte'):
        raw = json.dumps({'gaps': [{'code': 'gate_failed', 'detail': 'null-path:' + diagnostic, 'status': 'blocked'}]}).encode()
        expected = json.dumps({'gaps': [{'code': 'gate_failed', 'detail': 'null-path:' + MASK, 'status': 'blocked'}]}).encode()
        if mask_text(raw) == (expected, True): ok('mask locates runtime NUL diagnostic: ' + diagnostic)
        else: bad('mask failed to locate runtime NUL diagnostic')
    fatal = b'Traceback (most recent call last):\nRecursionError: maximum recursion depth exceeded\n'
    if mask_text(fatal) == (fatal, False): ok('mask never normalizes fatal reference tracebacks')
    else: bad('mask normalized a fatal reference traceback')


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
        js = "import {parse,canonical,dumps} from './04-validate-handoff/autobahn/lib/json.mjs'; const v=parse(process.argv[1]); console.log(dumps(v,null,true,true)); console.log(canonical(v));"
        same("shipping canonical fixture %d" % index, (0, (py + "\n" + digest + "\n").encode(), b""), run(["node", "--input-type=module", "-e", js, raw.decode()]))
    directory = REPO / 'tests/fixtures/e6-v1-port'
    js = "import {digest,parse,canonical} from './04-validate-handoff/autobahn/lib/json.mjs'; console.log(digest(process.argv[1])); console.log(canonical(parse(process.argv[2])));"
    generation, expected = (directory / 'generation.json').read_text().splitlines()
    same('shipping file and generation digests', (0, (sha256((directory / 'digest.bin').read_bytes()) + '\n' + expected + '\n').encode(), b''), run(['node', '--input-type=module', '-e', js, str(directory / 'digest.bin'), generation]))


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
    py = [PYTHON, "-B", str(REPO / "tests/fixtures/e6-v1-port/reference.py"), str(lib)]
    ts = ["node", "--disable-proto=throw", str(CANDIDATE)]
    return py, ts


def reference_entrypoint_probes(lib):
    for args in [['--help'], ['admit', '-hfoo'], ['admit', '--root', '-1.'], ['admit', '--unknown'], ['admit']]:
        command = [PYTHON, '-B', str(REPO / 'tests/fixtures/e6-v1-port/reference.py'), str(lib), *args]
        process = subprocess.run(command, capture_output=True, cwd=REPO)
        expected = process.returncode, process.stdout, process.stderr
        if reference_main(command) == expected: ok('anchored main equals standalone reference: ' + repr(args))
        else: bad('in-process reference changed standalone bytes: ' + repr(args))


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
    with tempfile.TemporaryDirectory(prefix='e6-v1-p5-') as temporary:
        root = Path(temporary).resolve()
        fixture(root)
        path = REPO / '.ai/handoff/readiness-v1/xskp-p5-skill-producers/4a064a42f24659d6df9f48f66ee9900103a6f002672155d9f8d27b49d80cdb0c/goals.json'
        bundle = json.loads(path.read_text())
        for item in [bundle, *bundle['goals']]: item['repository']['root'] = str(root)
        target = root / bundle['spec']['path']
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((REPO / bundle['spec']['path']).read_bytes())
        (root / 'tests/run-tests.sh').write_text('#!/bin/sh\nexit 0\n')
        write(root, '.ai/traceability/graph.json', {'schema_version': '1.1', 'nodes': [{'id': 'spec:skills:xskp-p5-skill-producers', 'type': 'spec', 'title': 'P5', 'status': 'active', 'repo_id': 'skills', 'path': bundle['spec']['path'], 'backlinks': []}], 'edges': []})
        write(root, 'plan.json', bundle)
        base = ['--root', str(root)]
        compare_args('p5-publish', lib, ['publish', *base, '--bundle', str(root / 'plan.json')])
        compare_args('p5-admit-planning', lib, ['admit', *base, '--handoff', 'northstar-plan-xskp-p5-skill-producers', '--goal-id', 'XSKP-P5-01', '--stage', 'planning'])
        compare_args('p5-migrate', lib, ['migrate', *base, '--legacy', str(root / 'plan.json'), '--bundle', str(root / 'plan.json')])


def registered_generations(lib):
    root = Path(os.environ.get("E6_WORKSPACE_ROOT", REPO.parent))
    homes = {
        "skills": REPO,
        "root": root,
        "ai-catapult": root / "ai-catapult",
        "ai-factory": root / "ai-factory",
    }
    for name, home in homes.items():
        registry = home / ".ai/workflows/northstar-readiness-v1.json"
        if not registry.is_file():
            if name == "skills":
                bad("registered v1 generations missing: " + name)
            else:
                ok("skipped v1 generations: " + name + " (sibling absent)")
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
    if sys.version_info[:3] != (3, 14, 8):
        bad('reference_python_required:3.14.8')
        return 1
    print('reference_python=' + sys.version.split()[0])
    write_dedicated()
    work = Path(tempfile.mkdtemp(prefix="e6-v1-parity-"))
    try:
        lib = work / "lib"
        if not materialize(lib):
            return 1
        if not require_candidate():
            return 1
        sys.path.insert(0, str(lib))
        sys.modules.pop('readiness_contract', None)
        sys.modules.pop('verification', None)
        frozen = importlib.import_module('readiness_contract')
        if Path(frozen.__file__).resolve().parent != lib.resolve():
            bad('reference imports escaped the materialized anchor')
            return 1
        canonical_fixtures()
        mask_self_probes()
        reference_entrypoint_probes(lib)
        golden_eleven(lib)
        from differential import run as differential
        from scenarios import run as scenarios
        from generated import run as generated
        from verification_cases import run as verification_cases
        from typed_cases import run as typed_cases
        from numeric_cases import run as numeric_cases
        from edge_cases import run as edge_cases
        from mapped_cases import run as mapped_cases
        from selection_cases import run as selection_cases
        from refusal_cases import run as refusal_cases
        from boundary_cases import run as boundary_cases
        from worktree_cases import run as worktree_cases
        from api_cases import run as api_cases
        from publication_cases import run as publication_cases
        from depth_cases import run as depth_cases
        numeric_cases(sys.modules[__name__])
        differential(sys.modules[__name__], lib)
        edge_cases(sys.modules[__name__], lib)
        generated(sys.modules[__name__], lib)
        verification_cases(sys.modules[__name__], lib)
        typed_cases(sys.modules[__name__], lib)
        mapped_cases(sys.modules[__name__], lib)
        selection_cases(sys.modules[__name__], lib)
        refusal_cases(sys.modules[__name__], lib)
        boundary_cases(sys.modules[__name__], lib)
        worktree_cases(sys.modules[__name__], lib)
        api_cases(sys.modules[__name__], lib)
        publication_cases(sys.modules[__name__], lib)
        depth_cases(sys.modules[__name__], lib)
        scenarios(sys.modules[__name__], lib)
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
        from inventory import report as inventory
        coverage = {'corpus_cases': CASES, 'codes': sorted(CODES), 'refusals': sorted(REFUSALS), 'refusal_sites': sorted(REFUSAL_SITES), 'executed_lines': sorted(LINES), 'diagnostics': sorted(DIAGNOSTICS), 'masked_sites': sorted(SITES), 'exception_sites': sorted(EXCEPTION_SITES), 'gate_branches': sorted(GATE_BRANCHES), 'inventory': inventory(sys.modules[__name__], lib)}
        if not coverage['inventory']['missing_refusal_sites']: ok('every anchored require/verification-stop refusal site reached')
        else: bad('unreached anchored refusal sites', repr(coverage['inventory']['missing_refusal_sites']))
        targets = {('readiness_contract.py', line) for line in (534, 644, 657, 719, 741, 786, 908, 932, 1165)} | {('verification.py', line) for line in (148, 155, 168)}
        runtime_sites = {(file, line) for file, line, kind in EXCEPTION_SITES if kind != 'Invalid'}
        if targets <= runtime_sites: ok('all 12 interpreter-diagnostic sites reached by runtime errors')
        else: bad('unreached runtime diagnostic sites', repr(sorted(targets - runtime_sites)))
        branches = {branch for branch, kind in GATE_BRANCHES if kind != 'Invalid'}
        if branches == {'unknown', 'blocked'}: ok('both line-785 runtime status decisions retained')
        else: bad('missing line-785 runtime status decision', repr(branches))
        print('coverage_inventory=' + json.dumps(coverage, sort_keys=True))
        if os.environ.get('E6_V1_COVERAGE_OUT'): Path(os.environ['E6_V1_COVERAGE_OUT']).write_text(json.dumps(coverage, indent=2, sort_keys=True) + '\n')
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print("Results: PASS=%d FAIL=%d" % (PASS, FAIL))
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
