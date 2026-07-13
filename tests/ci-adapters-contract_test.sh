#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RENDER="$ROOT/scripts/render-ci-adapters.py"
PROFILE="$ROOT/03-configure-generate/ai-catapult-init/templates/dot-ai/execution/profiles/execution/default.json"
GOAL6_PROFILE="$ROOT/tests/fixtures/ci-adapters/profiles/github-goal6-organization.json"
GOLDENS="$ROOT/tests/fixtures/ci-adapters/goldens"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
passed=0 failed=0
pass(){ echo "PASS $1"; passed=$((passed+1)); }
fail(){ echo "FAIL $1"; failed=$((failed+1)); }
expect(){ local name=$1 wanted=$2; shift 2; "$@" >/dev/null 2>&1; local rc=$?; if { [[ $wanted == pass && $rc -eq 0 ]] || [[ $wanted == fail && $rc -ne 0 ]]; }; then pass "$name"; else fail "$name (exit=$rc)"; fi; }

profile_for(){
  local hosts=$1 output=$2 preference=${3:-self-hosted}
  python3 - "$PROFILE" "$hosts" "$output" "$preference" <<'PY'
import json,sys
source,hosts,output,preference=sys.argv[1:]
profile=json.load(open(source))
profile['settings']['host_selection']=hosts.split(',')
profile['settings']['runner_preference']=preference
json.dump(profile,open(output,'w'),indent=2)
PY
}

for hosts in github ado gitlab github,ado,gitlab; do
  key="${hosts//,/-}"
  profile_for "$hosts" "$TMP/$key.json"
  expect "$key renders" pass python3 "$RENDER" --profile "$TMP/$key.json" --output "$TMP/$key"
  if diff -ru "$GOLDENS/$key" "$TMP/$key" >/dev/null; then pass "$key golden"; else fail "$key golden drift"; fi
  expect "$key check mode" pass python3 "$RENDER" --profile "$TMP/$key.json" --output "$TMP/$key" --check
done

profile_for gitlab,ado,github "$TMP/reversed.json"
python3 "$RENDER" --profile "$TMP/reversed.json" --output "$TMP/reversed" >/dev/null
if diff -ru "$GOLDENS/github-ado-gitlab" "$TMP/reversed" >/dev/null; then
  pass 'host selection order does not change projection bytes'
else
  fail 'host selection order changed projection bytes'
fi

[[ -f "$TMP/ado/azure-pipelines.yml" && ! -e "$TMP/ado/.github" && ! -e "$TMP/ado/.gitlab-ci.yml" ]] \
  && pass 'ADO selected-host-only files' || fail 'ADO emitted another provider'
[[ -f "$TMP/gitlab/.gitlab-ci.yml" && -f "$TMP/gitlab/.gitlab/dpua-child.yml" && ! -e "$TMP/gitlab/.github" && ! -e "$TMP/gitlab/azure-pipelines.yml" ]] \
  && pass 'GitLab selected-host-only files' || fail 'GitLab emitted another provider'
[[ -f "$TMP/github/.github/workflows/dpua-validation.yml" && ! -e "$TMP/github/azure-pipelines.yml" && ! -e "$TMP/github/.gitlab-ci.yml" ]] \
  && pass 'GitHub compatibility selected-host-only files' || fail 'GitHub emitted another provider'
expect 'Goal 6 organization-scoped GitHub profile remains compatible' pass \
  python3 "$RENDER" --profile "$GOAL6_PROFILE" --output "$TMP/goal6-github"

profile_for ado "$TMP/hosted.json" hosted
python3 "$RENDER" --profile "$TMP/hosted.json" --output "$TMP/hosted" >/dev/null
grep -q 'default: hosted' "$TMP/hosted/azure-pipelines.yml" \
  && pass 'explicit hosted preference rendered' || fail 'hosted preference missing'

grep -q -- '--max-retries 1' "$TMP/ado/azure-pipelines.yml" \
  && grep -q "stageDependencies.select" "$TMP/ado/azure-pipelines.yml" \
  && pass 'ADO one same-executor retry and conditional pool jobs' || fail 'ADO retry/pool contract missing'
grep -q -- '--max-retries 1' "$TMP/gitlab/.gitlab/dpua-child.yml" \
  && grep -q 'resolve-and-dispatch' "$TMP/gitlab/.gitlab-ci.yml" \
  && pass 'GitLab one same-executor retry and child dispatch' || fail 'GitLab retry/dispatch contract missing'
[[ $(grep -c 'actions/checkout@34e114' "$TMP/github/.github/workflows/dpua-validation.yml") -eq 3 ]] \
  && [[ $(grep -c 'moonrepo/setup-toolchain@261c62' "$TMP/github/.github/workflows/dpua-validation.yml") -eq 3 ]] \
  && pass 'GitHub jobs checkout source and install pinned toolchain' || fail 'GitHub runtime setup missing'

mkdir -p "$TMP/smoke/tools/ci-engine" "$TMP/smoke/.ai/execution/profiles/execution"
cp "$PROFILE" "$TMP/smoke/.ai/execution/profiles/execution/default.json"
cat > "$TMP/smoke/tools/ci-engine/provider_selector.py" <<'PY'
#!/usr/bin/env python3
import subprocess,sys
if '--' in sys.argv:
    marker=sys.argv.index('--')
    raise SystemExit(subprocess.run(sys.argv[marker+1:]).returncode)
if sys.argv[1] not in {'resolve','resolve-and-dispatch'}:
    raise SystemExit(2)
PY
python3 "$TMP/smoke/tools/ci-engine/provider_selector.py" resolve --provider github --profile "$TMP/smoke/.ai/execution/profiles/execution/default.json" --task-class validation --preference self-hosted \
  && python3 "$TMP/smoke/tools/ci-engine/provider_selector.py" execute --provider github --attempt 0 -- python3 -c 'print("smoke")' >/dev/null \
  && python3 "$TMP/smoke/tools/ci-engine/provider_selector.py" retry-transient --provider github --max-retries 1 -- python3 -c 'print("retry-smoke")' >/dev/null \
  && pass 'GitHub projected command contract executable smoke' || fail 'GitHub projected command smoke failed'

python3 - "$PROFILE" <<'PY' && pass 'canonical Goal 6 compatibility invariants' || fail 'Goal 6 compatibility invariants drifted'
import json,sys
s=json.load(open(sys.argv[1]))['settings']
assert s['runner_preference']=='self-hosted' and s['hosted_fallback'] is True
assert s['transient_retry']=={'max_retries':1,'classes':['provider-timed-out','executor-incomplete-after-heartbeat']}
assert s['github']['runner_scope']=='repository' and s['github']['required_read_permission']=='administration:read'
for host in ('github','ado','gitlab'):
    assert set(s[host]['fallback_excluded_tasks'])=={'release','publish','deployment','cas-write'}
    assert s[host]['max_redispatch_count']==0
assert s['ado']['adapter_status']=='experimental' and s['gitlab']['adapter_status']=='experimental'
PY

python3 - "$ROOT/03-configure-generate/ai-catapult-init/templates/dot-ai/execution/execution-profile.schema.json" <<'PY' \
  && pass 'published execution profile schema exposes bounded adapters' || fail 'published adapter schema is incomplete'
import json,sys
s=json.load(open(sys.argv[1]))
execution=s['allOf'][1]['then']['properties']['settings']
p=execution['properties']
assert set(p['host_selection']['items']['enum'])=={'github','ado','gitlab'}
assert p['transient_retry']['properties']['max_retries']['const']==1
assert p['ado']['allOf'][1]['properties']['max_redispatch_count']['const']==0
assert p['ado']['allOf'][1]['properties']['required_read_permission']['const']=='agent-pools:read'
assert p['gitlab']['allOf'][1]['properties']['required_read_permission']['const']=='read_api'
assert p['gitlab']['allOf'][1]['properties']['child_pipeline_file']['const']=='.gitlab/dpua-child.yml'
assert len(execution['allOf'])==3
PY

mutate(){
  local operation=$1 output=$2
  python3 - "$PROFILE" "$operation" "$output" <<'PY'
import json,sys
source,op,output=sys.argv[1:]
p=json.load(open(source));s=p['settings']
if op=='lore':s['host_selection']=['lore']
elif op=='duplicate':s['host_selection']=['ado','ado']
elif op=='retry':s['transient_retry']['max_retries']=2
elif op=='protected':s['host_selection']=['ado'];s['ado']['fallback_excluded_tasks'].remove('cas-write')
elif op=='threshold':s['host_selection']=['gitlab'];s['gitlab']['queue_age_threshold_seconds']=0
elif op=='permission':s['host_selection']=['ado'];s['ado']['required_read_permission']='admin'
elif op=='github-scope':s['host_selection']=['github'];s['github']['runner_scope']='organization';s['github']['required_read_permission']='self-hosted-runners:read'
elif op=='ado-demand-injection':s['host_selection']=['ado'];s['ado']['self_hosted_demands']=['Agent.OS -equals Linux\njobs:']
elif op=='ado-pool-injection':s['host_selection']=['ado'];s['ado']['self_hosted_pool']='safe\nsteps:'
elif op=='gitlab-tag-injection':s['host_selection']=['gitlab'];s['gitlab']['self_hosted_tags']=['safe, injected]']
elif op=='unknown':s['mystery']=True
json.dump(p,open(output,'w'))
PY
}
for operation in lore duplicate retry protected threshold permission github-scope ado-demand-injection ado-pool-injection gitlab-tag-injection unknown; do
  mutate "$operation" "$TMP/bad-$operation.json"
  expect "$operation fails closed" fail python3 "$RENDER" --profile "$TMP/bad-$operation.json" --output "$TMP/bad-$operation"
done

printf '\n' >> "$TMP/github/.github/workflows/dpua-validation.yml"
expect 'check rejects CI projection drift' fail python3 "$RENDER" --profile "$TMP/github.json" --output "$TMP/github" --check

# Existing workspaces retain unrelated files and only prior manifest-owned files
# are removed when host selection changes.
mkdir -p "$TMP/workspace/.ai"
printf '{}\n' > "$TMP/workspace/.ai/matrix.json"
printf 'keep-me\n' > "$TMP/workspace/KEEP.txt"
python3 "$RENDER" --profile "$TMP/ado.json" --output "$TMP/workspace" >/dev/null
python3 "$RENDER" --profile "$TMP/gitlab.json" --output "$TMP/workspace" >/dev/null
[[ $(cat "$TMP/workspace/KEEP.txt") == keep-me && ! -e "$TMP/workspace/azure-pipelines.yml" && -f "$TMP/workspace/.gitlab-ci.yml" ]] \
  && pass 'renderer preserves unrelated files and removes only stale owned output' || fail 'renderer mutated unrelated workspace content'

cp -R "$TMP/workspace" "$TMP/workspace-before-failure"
expect 'mid-promotion failure rolls back immediately' fail python3 "$RENDER" --profile "$TMP/ado.json" --output "$TMP/workspace" --fail-after-promote 2
if diff -ru "$TMP/workspace-before-failure" "$TMP/workspace" >/dev/null; then pass 'mid-promotion rollback restores exact files'; else fail 'mid-promotion rollback left partial files'; fi

expect 'injected process crash exits non-zero' fail python3 "$RENDER" --profile "$TMP/ado.json" --output "$TMP/workspace" --crash-after-promote 2
expect 'post-crash rerun recovers and converges' pass python3 "$RENDER" --profile "$TMP/ado.json" --output "$TMP/workspace"
[[ $(cat "$TMP/workspace/KEEP.txt") == keep-me && -f "$TMP/workspace/azure-pipelines.yml" && ! -e "$TMP/workspace/.gitlab-ci.yml" ]] \
  && pass 'crash recovery preserves unrelated files' || fail 'crash recovery damaged workspace'
expect 'post-intent crash exits non-zero' fail python3 "$RENDER" --profile "$TMP/gitlab.json" --output "$TMP/workspace" --crash-at after-intent
expect 'post-intent rerun recovers prior set' pass python3 "$RENDER" --profile "$TMP/ado.json" --output "$TMP/workspace"
expect 'post-commit crash exits non-zero' fail python3 "$RENDER" --profile "$TMP/gitlab.json" --output "$TMP/workspace" --crash-at after-commit
expect 'post-commit rerun retains committed set and cleans journal' pass python3 "$RENDER" --profile "$TMP/gitlab.json" --output "$TMP/workspace" --check
[[ ! -e "$TMP/workspace/.ai/execution/generated/.ci-adapters.journal.json" ]] \
  && pass 'committed recovery removes durable journal' || fail 'committed journal was not cleaned'

python3 "$RENDER" --profile "$TMP/gitlab.json" --output "$TMP/workspace" --hold-lock-seconds 2 >/dev/null 2>&1 & lock_pid=$!
sleep .2
expect 'workspace lock rejects concurrent renderer' fail python3 "$RENDER" --profile "$TMP/gitlab.json" --output "$TMP/workspace"
wait "$lock_pid" && pass 'workspace lock owner completes' || fail 'workspace lock owner failed'

mkdir -p "$TMP/collision/.ai"; printf '{}\n' > "$TMP/collision/.ai/matrix.json"; printf 'manual\n' > "$TMP/collision/azure-pipelines.yml"
expect 'unowned target collision fails closed' fail python3 "$RENDER" --profile "$TMP/ado.json" --output "$TMP/collision"
[[ $(cat "$TMP/collision/azure-pipelines.yml") == manual ]] && pass 'unowned collision remains unchanged' || fail 'unowned collision was overwritten'
mkdir -p "$TMP/unsafe"; printf 'keep\n' > "$TMP/unsafe/KEEP.txt"
expect 'arbitrary non-workspace output rejected' fail python3 "$RENDER" --profile "$TMP/ado.json" --output "$TMP/unsafe"
[[ $(cat "$TMP/unsafe/KEEP.txt") == keep ]] && pass 'unsafe output rejection is non-mutating' || fail 'unsafe output was mutated'

printf '\n%d passed; %d failed\n' "$passed" "$failed"
[[ $failed -eq 0 ]]
