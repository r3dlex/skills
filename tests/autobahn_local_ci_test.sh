#!/bin/bash
# Regression tests for executable local-safe CI derivation and composition.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CI_GATE="$REPO_ROOT/04-validate-handoff/autobahn/ci-gate.sh"
LOCAL_CI="$REPO_ROOT/04-validate-handoff/autobahn/local-ci.sh"
PASS=0; FAIL=0
ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
bad(){ echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
expect_block(){ local label="$1"; shift; if "$@" >/dev/null 2>&1; then bad "$label"; else ok "$label"; fi; }
repo(){ local r; r="$(mktemp -d)"; mkdir -p "$r/.github/workflows" "$r/tests"; echo "$r"; }
workflow(){ cat > "$1/.github/workflows/ci.yml"; }

if [[ -x "$LOCAL_CI" ]]; then ok "local-ci.sh exists and is executable"; else bad "local-ci.sh exists and is executable"; fi
if bash -n "$CI_GATE" && bash -n "$LOCAL_CI"; then ok "local-CI scripts parse"; else bad "local-CI scripts parse"; fi

r="$(repo)"
workflow "$r" <<'YAML'
name: local
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: bash tests/one.sh
      - run: bash tests/two.sh
YAML
printf '#!/bin/sh\nprintf "one\\n" >> order\n' > "$r/tests/one.sh"
printf '#!/bin/sh\nprintf "two\\n" >> order\n' > "$r/tests/two.sh"
chmod +x "$r/tests/"*.sh
if bash "$CI_GATE" --derive --root "$r" >/dev/null 2>&1 && [[ ! -e "$r/order" ]]; then ok "inventory discovery executes nothing"; else bad "inventory discovery executes nothing"; fi
if bash "$LOCAL_CI" --root "$r" >/dev/null 2>&1 && [[ "$(cat "$r/order" 2>/dev/null)" == $'one\ntwo' ]]; then ok "allowed CI commands run at root in order"; else bad "allowed CI commands run at root in order"; fi
rm -rf "$r"

for command in "npm run deploy" "npm run release:staging" "npm run publish-package" "moon run deploy" "moon run app:release" "moon run package:publish"; do
  r="$(repo)"
  workflow "$r" <<YAML
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: bash tests/mark.sh
      - run: $command
YAML
  printf '#!/bin/sh\ntouch marker\n' > "$r/tests/mark.sh"; chmod +x "$r/tests/mark.sh"
  expect_block "$command is not executable local CI" bash "$LOCAL_CI" --root "$r"
  [[ ! -e "$r/marker" ]] && ok "$command prevents every command from running" || bad "$command prevents every command from running"
  rm -rf "$r"
done

r="$(repo)"; workflow "$r" <<'YAML'
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: bash tests/fail.sh
YAML
printf '#!/bin/sh\nexit 7\n' > "$r/tests/fail.sh"; chmod +x "$r/tests/fail.sh"
expect_block "a nonzero CI command blocks" bash "$LOCAL_CI" --root "$r"
rm -rf "$r"

r="$(repo)"; workflow "$r" <<'YAML'
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: bash tests/mark.sh
      - run: curl https://example.invalid
YAML
printf '#!/bin/sh\ntouch marker\n' > "$r/tests/mark.sh"; chmod +x "$r/tests/mark.sh"
expect_block "the whole list is prevalidated before execution" bash "$LOCAL_CI" --root "$r"
if [[ ! -e "$r/marker" ]]; then ok "a forbidden later command prevents the first marker"; else bad "a forbidden later command prevents the first marker"; fi
rm -rf "$r"

for kind in missing empty malformed; do
  r="$(mktemp -d)"
  case "$kind" in
    missing) : ;;
    empty) mkdir -p "$r/.github/workflows"; printf 'jobs: {}\n' > "$r/.github/workflows/ci.yml" ;;
    malformed) mkdir -p "$r/.github/workflows"; printf 'jobs:\n\tbad: true\n' > "$r/.github/workflows/ci.yml" ;;
  esac
  expect_block "$kind CI blocks executable local CI" bash "$LOCAL_CI" --root "$r"
  rm -rf "$r"
done

r="$(repo)"; mkdir "$r/tmp"
workflow "$r" <<'YAML'
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: bash tests/mode.sh
YAML
cat > "$r/tests/mode.sh" <<'SH'
#!/bin/sh
set -- "$TMPDIR"/autobahn-local-ci.*
[ -f "$1" ] || exit 1
mode="$(stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1")"
[ "$mode" = 600 ]
SH
chmod +x "$r/tests/mode.sh"
if TMPDIR="$r/tmp" bash "$LOCAL_CI" --root "$r" >/dev/null 2>&1; then ok "temporary verification record is mode 0600"; else bad "temporary verification record is mode 0600"; fi
[[ -z "$(find "$r/tmp" -mindepth 1 -print -quit)" ]] && ok "mode-check temporary record is removed" || bad "mode-check temporary record is removed"
rm -rf "$r"

for context in uses with env defaults if working-directory shell strategy needs services container continue-on-error timeout-minutes expression; do
  r="$(repo)"
  case "$context" in
    uses) body=$'jobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/setup-node@v4\n      - run: bash tests/ok.sh' ;;
    with) body=$'jobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v4\n        with: { submodules: true }\n      - run: bash tests/ok.sh' ;;
    defaults) body=$'defaults: { run: { shell: bash } }\njobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: bash tests/ok.sh' ;;
    if) body=$'jobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: bash tests/ok.sh\n        if: always()' ;;
    working-directory) body=$'jobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: bash tests/ok.sh\n        working-directory: subdir' ;;
    shell) body=$'jobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: bash tests/ok.sh\n        shell: python' ;;
    continue-on-error) body=$'jobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: bash tests/ok.sh\n        continue-on-error: true' ;;
    expression) body=$'jobs:\n  test:\n    runs-on: ${{ matrix.os }}\n    steps:\n      - run: bash tests/ok.sh' ;;
    *)
      case "$context" in
        env) extra='    env: { CI: true }' ;;
        strategy) extra='    strategy: { matrix: { os: [ubuntu-latest] } }' ;;
        needs) extra='    needs: build' ;;
        services) extra='    services: { db: { image: postgres } }' ;;
        container) extra='    container: node:20' ;;
        timeout-minutes) extra='    timeout-minutes: 1' ;;
      esac
      body="jobs:
  test:
    runs-on: ubuntu-latest
$extra
    steps:
      - run: bash tests/ok.sh" ;;
  esac
  printf '%s\n' "$body" > "$r/.github/workflows/ci.yml"
  printf '#!/bin/sh\ntouch marker\n' > "$r/tests/ok.sh"; chmod +x "$r/tests/ok.sh"
  expect_block "unsupported $context context blocks" bash "$LOCAL_CI" --root "$r"
  [[ ! -e "$r/marker" ]] && ok "unsupported $context runs nothing" || bad "unsupported $context runs nothing"
  rm -rf "$r"
done

for provider in azure gitlab; do
  r="$(mktemp -d)"; mkdir -p "$r/tests"
  printf '#!/bin/sh\ntouch marker\n' > "$r/tests/ok.sh"; chmod +x "$r/tests/ok.sh"
  if [[ "$provider" == azure ]]; then
    printf 'steps:\n  - script: bash tests/ok.sh\n' > "$r/azure-pipelines.yml"
  else
    printf 'test:\n  script:\n    - bash tests/ok.sh\n' > "$r/.gitlab-ci.yml"
  fi
  expect_block "$provider is inventory-only, not executable locally" bash "$LOCAL_CI" --root "$r"
  [[ ! -e "$r/marker" ]] && ok "$provider executable mode runs nothing" || bad "$provider executable mode runs nothing"
  rm -rf "$r"
done

r="$(repo)"; workflow "$r" <<'YAML'
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: bash tests/ok.sh
YAML
printf '#!/bin/sh\ntouch checkout-ran\n' > "$r/tests/ok.sh"; chmod +x "$r/tests/ok.sh"
if bash "$LOCAL_CI" --root "$r" >/dev/null 2>&1 && [[ -f "$r/checkout-ran" ]]; then ok "exact checkout without with is a local no-op"; else bad "exact checkout without with is a local no-op"; fi
rm -rf "$r"

for duplicate in job runs-on steps; do
  r="$(repo)"
  case "$duplicate" in
    job) body=$'  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: bash tests/ok.sh\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: bash tests/ok.sh' ;;
    runs-on) body=$'  test:\n    runs-on: ubuntu-latest\n    runs-on: macos-latest\n    steps:\n      - run: bash tests/ok.sh' ;;
    steps) body=$'  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: bash tests/ok.sh\n    steps:\n      - run: bash tests/ok.sh' ;;
  esac
  printf 'jobs:\n%s\n' "$body" > "$r/.github/workflows/ci.yml"
  printf '#!/bin/sh\ntouch marker\n' > "$r/tests/ok.sh"; chmod +x "$r/tests/ok.sh"
  expect_block "duplicate $duplicate mapping blocks" bash "$LOCAL_CI" --root "$r"
  [[ ! -e "$r/marker" ]] && ok "duplicate $duplicate runs nothing" || bad "duplicate $duplicate runs nothing"
  rm -rf "$r"
done

r="$(repo)"; workflow "$r" <<'YAML'
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: |
          echo first
          echo second
YAML
json="$(bash "$CI_GATE" --derive-json --root "$r" 2>/dev/null || true)"
if JSON="$json" python3 - <<'PY'
import json, os
try: x=json.loads(os.environ['JSON'])
except Exception: raise SystemExit(1)
assert len(x) == 1
assert [line.strip() for line in x[0].splitlines()] == ["echo first", "echo second"]
PY
then ok "a multiline step stays one JSON element"; else bad "a multiline step stays one JSON element"; fi
expect_block "a multiline shell block is safely rejected for execution" bash "$LOCAL_CI" --root "$r"
rm -rf "$r"

r="$(repo)"; workflow "$r" <<'YAML'
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: bash tests/tick.sh
      - run: bash tests/tick.sh
YAML
printf '#!/bin/sh\necho x >> ticks\n' > "$r/tests/tick.sh"; chmod +x "$r/tests/tick.sh"
json="$(bash "$CI_GATE" --derive-json --root "$r" 2>/dev/null || true)"
if JSON="$json" python3 - <<'PY'
import json, os
assert len(json.loads(os.environ['JSON'])) == 2
PY
then ok "structured derivation preserves duplicates"; else bad "structured derivation preserves duplicates"; fi
if bash "$LOCAL_CI" --root "$r" >/dev/null 2>&1 && [[ "$(wc -l < "$r/ticks" | tr -d ' ')" == 2 ]]; then ok "duplicate steps execute twice"; else bad "duplicate steps execute twice"; fi
rm -rf "$r"

# A dedicated TMPDIR makes cleanup observable without a production test hook.
for result in success failure; do
  r="$(repo)"; workflow "$r" <<YAML
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: bash tests/$result.sh
YAML
  if [[ "$result" == success ]]; then code=0; else code=1; fi
  printf '#!/bin/sh\nexit %s\n' "$code" > "$r/tests/$result.sh"; chmod +x "$r/tests/$result.sh"
  mkdir "$r/tmp"
  TMPDIR="$r/tmp" bash "$LOCAL_CI" --root "$r" >/dev/null 2>&1 || true
  if [[ -z "$(find "$r/tmp" -mindepth 1 -print -quit)" ]]; then ok "temporary record is removed after $result"; else bad "temporary record is removed after $result"; fi
  rm -rf "$r"
done

echo ""; echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
