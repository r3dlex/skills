#!/bin/bash
#
# knowledge_contract_fingerprint_test.sh
#
# XSKP-P5-01 regression guard: the frozen knowledge contract pack (pack version
# 1) exists in TWO byte-identical places — the planning copy beside the spec
# (docs/specifications/ACTIVE/cross-surface-knowledge-publication.contract) and
# the published copy (.ai/knowledge/contract). The lock is the identity:
#
#   - contract.lock.json sha256 is pinned to
#     9f5d7edfc17554c383b06aa4726dfffe564ecc8d657b16baa89ce72098d5e102
#     in both copies,
#   - every file the lock lists must hash exactly as the lock says, in both
#     copies,
#   - both copies must be byte-identical trees,
#   - the on-disk file set of both copies must equal the lock's listed set
#     (os-noise like .DS_Store is ignored), and
#   - the checker below must go RED on a single mutated byte in a temp copy.
#
# Exit 0 when all checks pass; non-zero otherwise.
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CONTRACT_SRC="docs/specifications/ACTIVE/cross-surface-knowledge-publication.contract"
CONTRACT_COPY=".ai/knowledge/contract"
LOCK_PIN="9f5d7edfc17554c383b06aa4726dfffe564ecc8d657b16baa89ce72098d5e102"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# verify_pack <dir>: exits 0 only when <dir>/contract.lock.json parses and lists
# files, every listed file's sha256 matches the lock within <dir>, and the
# on-disk file set equals the lock's listed set plus the lock itself
# (macOS-noise .DS_Store is ignored). On failure, prints the failing relations.
verify_pack() {
  python3 - "$1" <<'PY'
import hashlib, json, os, sys
root = sys.argv[1]
try:
    with open(os.path.join(root, "contract.lock.json"), "rb") as fh:
        lock = json.load(fh)
except (OSError, ValueError) as err:
    print(f"lock unreadable: {err}")
    sys.exit(2)
files = lock.get("files")
if not isinstance(files, dict) or not files:
    print("contract.lock.json lists no files")
    sys.exit(2)
bad = 0
for rel in sorted(files):
    expected = files[rel]
    p = os.path.join(root, rel)
    try:
        with open(p, "rb") as fh:
            actual = hashlib.sha256(fh.read()).hexdigest()
    except OSError as err:
        print(f"unreadable: {rel}: {err}")
        bad += 1
        continue
    if actual != expected:
        print(f"mismatch: {rel}")
        bad += 1
known = set(files) | {"contract.lock.json"}
on_disk = set()
for base, _dirs, names in os.walk(root):
    for name in names:
        if name == ".DS_Store":
            continue
        on_disk.add(os.path.relpath(os.path.join(base, name), root))
for rel in sorted(on_disk - known):
    print(f"orphan: {rel}")
    bad += 1
for rel in sorted(known - on_disk - {"contract.lock.json"}):
    print(f"not-on-disk: {rel}")
    bad += 1
sys.exit(1 if bad else 0)
PY
}

# lock_sha <dir>: sha256 of <dir>/contract.lock.json, or a diagnosis token.
lock_sha() {
  python3 -c 'import hashlib, os, sys
p = os.path.join(sys.argv[1], "contract.lock.json")
try:
    with open(p, "rb") as fh:
        data = fh.read()
except FileNotFoundError:
    print("missing")
except OSError as err:
    print(f"unreadable: {err}")
else:
    print(hashlib.sha256(data).hexdigest())' "$1"
}

# 1. Each copy parses and validates against the lock it carries (attributed).
SRC_OK=1
COPY_OK=1
SRC_PACK_OUT=""
COPY_PACK_OUT=""
if ! SRC_PACK_OUT="$(verify_pack "$CONTRACT_SRC")"; then SRC_OK=0; fi
if ! COPY_PACK_OUT="$(verify_pack "$CONTRACT_COPY")"; then COPY_OK=0; fi
if [ "$SRC_OK" -eq 1 ] && [ "$COPY_OK" -eq 1 ]; then
  ok "both contract copies validate against contract.lock.json"
else
  [ "$SRC_OK" -eq 1 ] || bad "source contract copy fails lock validation: $SRC_PACK_OUT"
  [ "$COPY_OK" -eq 1 ] || bad "published contract copy (.ai/knowledge) fails lock validation: $COPY_PACK_OUT"
fi

# 2. The lock is pinned; both copies must carry the identical pinned lock bytes.
SRC_LOCK_SHA="$(lock_sha "$CONTRACT_SRC")"
COPY_LOCK_SHA="$(lock_sha "$CONTRACT_COPY")"
if [ "$SRC_LOCK_SHA" = "$LOCK_PIN" ] && [ "$COPY_LOCK_SHA" = "$LOCK_PIN" ]; then
  ok "contract.lock.json pinned in both copies ($LOCK_PIN)"
else
  bad "contract.lock.json sha not pinned (src=$SRC_LOCK_SHA copy=$COPY_LOCK_SHA)"
fi

# 3. The two copies are byte-identical trees.
if diff -r "$CONTRACT_SRC" "$CONTRACT_COPY" >/dev/null 2>&1; then
  ok "contract copies are byte-identical trees"
else
  bad "contract copies are not byte-identical trees"
fi

# 4. The checker must go red on a mutated byte in a temp copy.
TMPDIR_P5="$(mktemp -d "${TMPDIR:-/tmp}/xskp-p5-01.fingerprint.XXXXXX")"
trap 'rm -rf "$TMPDIR_P5"' EXIT
cp -R "$CONTRACT_SRC/." "$TMPDIR_P5/"
# Mutate one byte of one lock-listed file: flip a bit of conformance.json
# (an empty file is overwritten, which changes its bytes just as surely).
python3 - "$TMPDIR_P5" <<'PY'
import os, sys
target = os.path.join(sys.argv[1], "conformance.json")
with open(target, "rb") as fh:
    data = bytearray(fh.read())
if len(data) == 0:
    data = bytearray(b"P5")
else:
    data[0] ^= 0x01
with open(target, "wb") as fh:
    fh.write(data)
PY
if verify_pack "$TMPDIR_P5" >/dev/null 2>&1; then
  bad "checker tolerated a mutated byte in a temp copy"
else
  ok "checker goes red on a mutated byte in a temp copy"
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1