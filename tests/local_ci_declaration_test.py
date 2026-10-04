"""local_ci declaration contract for .ai/workflows/repo-workflow.json (af-06).

The normative definition lives in
03-configure-generate/ai-catapult-init/modules/workflow.md. The declaration
shape is exactly:

    "local_ci": {
        "surfaces": [{"cmd": str, "hermetic": bool, "covers": str}, ...],
        "sole_source_of_truth": bool
    }

An absent or empty declaration is never defaulted, guessed or probed: the
consumer parks. A malformed declaration is rejected with the offending JSON
path named. A flat command string or list is not a valid declaration.
"""
import json
import pathlib
import sys
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]
TEMPLATE = (REPO / "03-configure-generate/ai-catapult-init/templates"
            / "dot-ai/workflows/repo-workflow.json")
SCHEMA_DOC = (REPO / "03-configure-generate/ai-catapult-init/modules/workflow.md")
FIXTURES = ("standalone", "umbrella")

DECL_KEYS = ("surfaces", "sole_source_of_truth")
SURFACE_KEYS = ("cmd", "hermetic", "covers")


class Malformed(Exception):
    """A malformed declaration; str() names the offending JSON path first."""

    def __init__(self, path, message):
        self.path = path
        super().__init__(f"{path}: {message}")


def validate_local_ci(manifest):
    """Return (state, surfaces) with state in {'absent', 'empty', 'declared'}.

    Absence is absence: no default is inserted and no command is guessed.
    """
    if "local_ci" not in manifest:
        return "absent", []
    decl = manifest["local_ci"]
    if not isinstance(decl, dict):
        raise Malformed("local_ci", "must be an object with keys "
                        f"{list(DECL_KEYS)}, got {type(decl).__name__}")
    for key in sorted(k for k in decl if k not in DECL_KEYS):
        raise Malformed(f"local_ci.{key}", "unknown field")
    for key in DECL_KEYS:
        if key not in decl:
            raise Malformed(f"local_ci.{key}", "missing required field")
    surfaces = decl["surfaces"]
    if not isinstance(surfaces, list):
        raise Malformed("local_ci.surfaces",
                        "must be a list of {cmd, hermetic, covers} surfaces; "
                        "a flat command string or list is not a declaration")
    if any(not isinstance(surface, dict) for surface in surfaces):
        raise Malformed("local_ci.surfaces",
                        "must be a list of {cmd, hermetic, covers} surfaces; "
                        "a flat command list is not a declaration")
    for index, surface in enumerate(surfaces):
        path = f"local_ci.surfaces[{index}]"
        for key in sorted(k for k in surface if k not in SURFACE_KEYS):
            raise Malformed(f"{path}.{key}", "unknown field")
        for key in SURFACE_KEYS:
            if key not in surface:
                raise Malformed(f"{path}.{key}", "missing required field")
        if not isinstance(surface["cmd"], str) or not surface["cmd"].strip():
            raise Malformed(f"{path}.cmd", "must be a non-empty string")
        if not isinstance(surface["hermetic"], bool):
            raise Malformed(f"{path}.hermetic", "must be a boolean")
        if not isinstance(surface["covers"], str) or not surface["covers"].strip():
            raise Malformed(f"{path}.covers", "must be a non-empty string")
    sole = decl["sole_source_of_truth"]
    if not isinstance(sole, bool):
        raise Malformed("local_ci.sole_source_of_truth", "must be a boolean")
    if sole and not surfaces:
        raise Malformed("local_ci.sole_source_of_truth",
                        "cannot claim sole source of truth over zero surfaces")
    if not surfaces:
        return "empty", []
    return "declared", list(surfaces)


def consumer_verdict(manifest):
    """Return ('verify', surfaces) or ('park', reason).

    The consumer rule from the schema doc: anything but an authoritative
    declaration parks; a consumer never probes for a command.
    """
    state, surfaces = validate_local_ci(manifest)
    if state == "absent":
        return "park", "local_ci absent"
    if state == "empty":
        return "park", "local_ci empty"
    if not manifest["local_ci"]["sole_source_of_truth"]:
        return "park", "not the sole source of truth"
    return "verify", surfaces


class ShapeContract(unittest.TestCase):
    """Validator cases: well-formed accepted, malformed rejected, absent as absent."""

    def well_formed(self, *surfaces, sole=True):
        return {"local_ci": {"surfaces": list(surfaces),
                             "sole_source_of_truth": sole}}

    def surface(self, cmd="bash tests/run-tests.sh", hermetic=True,
                covers="test suite"):
        return {"cmd": cmd, "hermetic": hermetic, "covers": covers}

    def test_well_formed_declaration_accepted(self):
        manifest = self.well_formed(self.surface())
        self.assertEqual(validate_local_ci(manifest), ("declared", [self.surface()]))
        self.assertEqual(consumer_verdict(manifest)[0], "verify")

    def test_well_formed_multi_surface_per_surface_hermeticity(self):
        offline = self.surface(hermetic=True, covers="offline checks")
        hosted = self.surface(cmd="gh run list", hermetic=False,
                              covers="hosted reconciliation")
        manifest = self.well_formed(offline, hosted)
        state, surfaces = validate_local_ci(manifest)
        self.assertEqual(state, "declared")
        self.assertEqual([s["hermetic"] for s in surfaces], [True, False])

    def test_malformed_rejected_with_offending_path(self):
        cases = [
            # (offending path, local_ci value)
            ("local_ci", "bash tests/run-tests.sh"),
            ("local_ci", ["bash tests/run-tests.sh"]),
            ("local_ci", None),
            ("local_ci.surfaces", {"sole_source_of_truth": True}),
            ("local_ci.sole_source_of_truth", {"surfaces": [self.surface()]}),
            ("local_ci.extra",
             {"surfaces": [], "sole_source_of_truth": False, "extra": 1}),
            ("local_ci.surfaces",
             {"surfaces": "bash tests/run-tests.sh",
              "sole_source_of_truth": False}),
            ("local_ci.surfaces",
             {"surfaces": ["bash tests/run-tests.sh", "bash other.sh"],
              "sole_source_of_truth": False}),
            ("local_ci.surfaces", {"surfaces": [42],
                                   "sole_source_of_truth": False}),
            ("local_ci.surfaces[0].cmd",
             {"surfaces": [{"hermetic": True, "covers": "t"}],
              "sole_source_of_truth": False}),
            ("local_ci.surfaces[0].cmd",
             {"surfaces": [self.surface(cmd="")], "sole_source_of_truth": False}),
            ("local_ci.surfaces[0].hermetic",
             {"surfaces": [self.surface(hermetic="yes")],
              "sole_source_of_truth": False}),
            ("local_ci.surfaces[0].covers",
             {"surfaces": [self.surface(covers="")], "sole_source_of_truth": False}),
            ("local_ci.surfaces[0].covers",
             {"surfaces": [dict(self.surface(), covers=["tests"])],
              "sole_source_of_truth": False}),
            ("local_ci.surfaces[0].extra",
             {"surfaces": [dict(self.surface(), extra=1)],
              "sole_source_of_truth": False}),
            ("local_ci.sole_source_of_truth",
             {"surfaces": [self.surface()], "sole_source_of_truth": "yes"}),
            ("local_ci.sole_source_of_truth",
             {"surfaces": [], "sole_source_of_truth": True}),
        ]
        for path, decl in cases:
            with self.subTest(path=path, decl=decl):
                with self.assertRaises(Malformed) as caught:
                    validate_local_ci({"local_ci": decl})
                self.assertEqual(caught.exception.path, path, str(caught.exception))
                self.assertIn(path, str(caught.exception))
                # A consumer refuses a malformed declaration outright: it is
                # never repaired, defaulted or replaced by a probed command.
                with self.assertRaises(Malformed):
                    consumer_verdict({"local_ci": decl})

    def test_flat_command_list_is_not_a_declaration(self):
        # The multi-surface shape exists because one string cannot express a
        # two-surface definition with per-surface hermeticity.
        for decl in ("bash tests/run-tests.sh", ["bash tests/run-tests.sh"],
                     {"commands": ["bash tests/run-tests.sh"]}):
            with self.subTest(decl=decl):
                with self.assertRaises(Malformed) as caught:
                    validate_local_ci({"local_ci": decl})
                self.assertIn("local_ci", caught.exception.path)

    def test_absence_is_absence(self):
        state, surfaces = validate_local_ci({})
        self.assertEqual((state, surfaces), ("absent", []))
        self.assertEqual(consumer_verdict({})[0], "park")
        self.assertEqual(consumer_verdict({})[1], "local_ci absent")

    def test_empty_declaration_parks(self):
        manifest = self.well_formed(sole=False)
        self.assertEqual(validate_local_ci(manifest), ("empty", []))
        self.assertEqual(consumer_verdict(manifest)[0], "park")

    def test_surfaces_without_sole_truth_claim_park(self):
        manifest = self.well_formed(self.surface(), sole=False)
        self.assertEqual(validate_local_ci(manifest)[0], "declared")
        self.assertEqual(consumer_verdict(manifest)[0], "park")


class ScaffoldAndFixtures(unittest.TestCase):
    """The scaffold, the v3 reference fixtures and the schema doc."""

    def test_scaffold_ships_park_until_derived_declaration(self):
        # A freshly initialized repo carries the field, well-formed, and never
        # a guessed command: the starter is empty until the owner derives one.
        manifest = json.loads(TEMPLATE.read_text())
        self.assertIn("local_ci", manifest,
                      "scaffold repo-workflow.json must carry local_ci")
        state, surfaces = validate_local_ci(manifest)
        self.assertEqual(state, "empty")
        self.assertEqual(surfaces, [])
        self.assertIs(manifest["local_ci"]["sole_source_of_truth"], False)
        self.assertEqual(consumer_verdict(manifest)[0], "park")

    def test_reference_fixtures_carry_well_formed_declarations(self):
        for variant in FIXTURES:
            root = REPO / "reference/fixtures/v3" / variant
            manifest = json.loads(
                (root / ".ai/workflows/repo-workflow.json").read_text())
            with self.subTest(variant=variant):
                self.assertIn("local_ci", manifest,
                              f"{variant} fixture must carry local_ci")
                state, surfaces = validate_local_ci(manifest)
                self.assertEqual(state, "declared")
                self.assertTrue(surfaces)
                self.assertIs(manifest["local_ci"]["sole_source_of_truth"], True)
                self.assertEqual(consumer_verdict(manifest)[0], "verify")
                for surface in surfaces:
                    # A declared surface names something that exists.
                    script = surface["cmd"].split()[-1]
                    self.assertTrue((root / script).is_file(),
                                    f"{variant}: declared surface missing: "
                                    f"{surface['cmd']}")

    def test_schema_doc_states_park_rule_and_shape(self):
        doc = SCHEMA_DOC.read_text()
        self.assertIn("absent or empty", doc)
        self.assertIn("park", doc)
        self.assertIn("never probe", doc)
        self.assertIn("flat", doc)
        for token in ("surfaces", "sole_source_of_truth", "hermetic", "covers"):
            self.assertIn(token, doc, f"schema doc must define {token}")


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if result.wasSuccessful():
        print(f"Results: PASS={result.testsRun} FAIL=0")
    sys.exit(0 if result.wasSuccessful() else 1)
