#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; T="$ROOT/scripts/matrix-contract.py"; X="$(mktemp -d)"; trap 'rm -rf "$X"' EXIT
P=0;F=0; ok(){ echo "PASS $1";P=$((P+1));}; bad(){ echo "FAIL $1";F=$((F+1));}; expect(){ local n=$1 w=$2;shift 2;"$@" >/dev/null 2>&1;local r=$?;{ [ "$w" = pass ]&&[ $r -eq 0 ];}||{ [ "$w" = fail ]&&[ $r -ne 0 ];}&&ok "$n"||bad "$n ($r)";}
mkdir -p "$X/profiles"/{checkout,execution,toolchain,cas} "$X/overrides"
cat > "$X/profiles/checkout/default.json" <<'J'
{"schema_version":"1.0","profile_type":"checkout","profile_id":"default","version":"1.0","settings":{"history":"full","disposable":false}}
J
cat > "$X/profiles/execution/default.json" <<'J'
{"schema_version":"1.0","profile_type":"execution","profile_id":"default","version":"1.0","settings":{"runner_preference":"self-hosted","host_selection":["github"],"hosted_fallback":true}}
J
cat > "$X/profiles/toolchain/default.json" <<'J'
{"schema_version":"1.0","profile_type":"toolchain","profile_id":"default","version":"1.0","settings":{"tier":"managed"}}
J
cat > "$X/profiles/cas/default.json" <<'J'
{"schema_version":"1.0","profile_type":"cas","profile_id":"default","version":"1.0","settings":{"mode":"pull-only"}}
J
cat > "$X/v10.json" <<'J'
{"schema_version":"1.0","topology_type":"umbrella","max_allowed_depth":3,"current_depth":1,"sync_strategy":"physical-copy","upstream_authority":{"type":"git","url":"https://github.com/acme/root.git","ref":"main"},"managed_repositories":[{"path":"one","depth":1,"inherits_assets_from":"."}],"inherited_assets":[],"sync_status":{}}
J
cat > "$X/v11.json" <<'J'
{"schema_version":"1.1","repository_id":"parent","topology_type":"umbrella","max_allowed_depth":3,"current_depth":1,"sync_strategy":"physical-copy","upstream_authority":{"type":"git","url":"https://github.com/acme/root.git","ref":"main"},"managed_repositories":[{"repo_id":"one","path":"one","depth":1,"inherits_assets_from":".","canonical_origin":"https://github.com/acme/one.git","canonical_upstream":null,"default_ref":"main","disposable":false,"moon_project_id":"one","dependencies":[],"profile_refs":{"checkout":{"type":"checkout","id":"default","version":"1.0"},"execution":{"type":"execution","id":"default","version":"1.0"},"toolchain":{"type":"toolchain","id":"default","version":"1.0"},"cas":{"type":"cas","id":"default","version":"1.0"}}},{"repo_id":"two","path":"two","depth":1,"inherits_assets_from":".","canonical_origin":"git@github.com:acme/two.git","canonical_upstream":"https://github.com/upstream/two.git","default_ref":"main","disposable":true,"moon_project_id":"two","dependencies":["one"],"profile_refs":{"checkout":{"type":"checkout","id":"default","version":"1.0"},"execution":{"type":"execution","id":"default","version":"1.0"},"toolchain":{"type":"toolchain","id":"default","version":"1.0"},"cas":{"type":"cas","id":"default","version":"1.0"}}}],"inherited_assets":[{"path":"AGENTS.md","source":".","mode":"physical-copy"}],"sync_status":{}}
J
V=(python3 "$T" validate --profiles "$X/profiles"); G=(python3 "$T" project --profiles "$X/profiles" --overrides "$X/overrides" --output "$X/out")
expect 'v1.0 dual reader' pass "${V[@]}" --matrix "$X/v10.json"; expect 'complete v1.1 validates' pass "${V[@]}" --matrix "$X/v11.json"; "${G[@]}" --matrix "$X/v11.json" || bad 'initial projection'
python3 - "$X/v11.json" "$X/standalone.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]));d.update(topology_type='standalone',max_allowed_depth=0,current_depth=0,managed_repositories=[]);json.dump(d,open(sys.argv[2],'w'))
PY
expect 'empty standalone depth validates' pass "${V[@]}" --matrix "$X/standalone.json"
python3 - "$X/v11.json" "$X/multi-host.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]));d['upstream_authority']['url']='https://dev.azure.com/acme/project/_git/root';d['managed_repositories'][0]['canonical_origin']='https://gitlab.com/acme/one.git';json.dump(d,open(sys.argv[2],'w'))
PY
expect 'GitLab and ADO canonical URLs validate' pass "${V[@]}" --matrix "$X/multi-host.json"
python3 - "$X/out/one.json" <<'PY' && ok 'sanitized child projection contract' || bad 'sanitized child projection contract'
import json,sys
p=json.load(open(sys.argv[1]));raw=open(sys.argv[1]).read();assert p['parent_repo_id']=='parent' and p['profile_versions']=={'checkout':'1.0','execution':'1.0','toolchain':'1.0','cas':'1.0'} and len(p['inheritance_digest'])==64 and 'two' not in raw and 'hosted_fallback' not in raw
PY
cat > "$X/overrides/one.json" <<'J'
{"runner_preference":"hosted"}
J
"${G[@]}" --matrix "$X/v11.json";python3 -c "import json;assert json.load(open('$X/out/one.json'))['local_overrides']['runner_preference']=='hosted'"&&ok 'separate override input preserved'||bad 'separate override input'
cp -R "$X/out" "$X/before";expect 'mid-render failure' fail "${G[@]}" --matrix "$X/v11.json" --fail-after 1;diff -ru "$X/before" "$X/out" >/dev/null&&ok 'mid-render unchanged'||bad 'mid-render mutated'
# durable intent and rename-phase crash recovery
"${G[@]}" --matrix "$X/v11.json" --crash-at after-intent >/dev/null 2>&1
"${G[@]}" --matrix "$X/v11.json"&&ok 'post-intent crash recovered'||bad 'post-intent recovery'
"${G[@]}" --matrix "$X/v11.json" --crash-at after-backup >/dev/null 2>&1
"${G[@]}" --matrix "$X/v11.json"&&ok 'post-backup crash recovered'||bad 'post-backup recovery'
"${G[@]}" --matrix "$X/v11.json" --crash-at after-promote >/dev/null 2>&1
"${G[@]}" --matrix "$X/v11.json"&&ok 'post-promote crash recovered'||bad 'post-promote recovery'
# live lock and stale lock
"${G[@]}" --matrix "$X/v11.json" --hold-lock-seconds 2 >/dev/null 2>&1 & hp=$!;sleep .2;expect 'live lock blocks concurrent writer' fail "${G[@]}" --matrix "$X/v11.json";wait $hp
printf '{"pid":%s,"created_at":0,"token":"live-owner"}\n' "$$" > "$X/.out.lock";expect 'old live lock is never stolen' fail "${G[@]}" --matrix "$X/v11.json" --stale-after 1;rm "$X/.out.lock"
: > "$X/.out.lock";expect 'malformed initialization recovers' pass "${G[@]}" --matrix "$X/v11.json"
python3 - "$X/.out.lock.recovery" <<'PY'
import fcntl,os,sys
fd=os.open(sys.argv[1],os.O_CREAT|os.O_RDWR,0o600);fcntl.flock(fd,fcntl.LOCK_EX);os._exit(88)
PY
printf '{"pid":999999,"created_at":0,"token":"orphan-recovery"}\n' > "$X/.out.lock";expect 'orphaned recovery mutex crash releases lock' pass "${G[@]}" --matrix "$X/v11.json"
printf '{"pid":999999,"created_at":0}\n' > "$X/.out.lock";expect 'stale lock recovered' pass "${G[@]}" --matrix "$X/v11.json" --stale-after 1
printf '{"pid":999999,"created_at":0,"token":"stale-owner"}\n' > "$X/.out.lock"
"${G[@]}" --matrix "$X/v11.json" --hold-lock-seconds 2 >/dev/null 2>&1 & ap=$!;sleep .2
expect 'stale ABA contender cannot move new live lock' fail "${G[@]}" --matrix "$X/v11.json"
kill -0 "$ap" 2>/dev/null&&ok 'stale ABA winner remains owner'||bad 'stale ABA winner lost ownership';wait "$ap"
expect 'check current' pass "${G[@]}" --matrix "$X/v11.json" --check;printf '\n' >> "$X/out/two.json";expect 'check drift' fail "${G[@]}" --matrix "$X/v11.json" --check
mut(){ python3 - "$X/v11.json" "$X/bad.json" "$1" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]));op=sys.argv[3]
if op=='cycle':d['managed_repositories'][0]['dependencies']=['two']
elif op=='unknown':d['managed_repositories'][0]['extra']=1
elif op=='path':d['managed_repositories'][0]['path']='../one'
elif op=='skew':d['managed_repositories'][0]['profile_refs']['cas']['version']='2.0'
elif op=='ref':d['managed_repositories'][0]['default_ref']='bad ref'
elif op=='inherits':d['managed_repositories'][0]['inherits_assets_from']='../escape'
elif op=='topology':d['max_allowed_depth']=2
elif op=='current-depth':d['current_depth']=0
elif op=='authority':d['upstream_authority']['type']='local'
elif op=='url':d['managed_repositories'][0]['canonical_origin']='https://evil.example/repo.git'
elif op=='credential':d['managed_repositories'][0]['canonical_origin']='https://token@github.com/acme/one.git'
elif op=='migration-type':d['migration']=[]
elif op=='exclusion-path':d['exclusions']=['../escape']
json.dump(d,open(sys.argv[2],'w'))
PY
}
for op in cycle unknown path skew ref inherits topology current-depth authority url credential migration-type exclusion-path;do mut $op;expect "$op rejects" fail "${V[@]}" --matrix "$X/bad.json";done
python3 - "$ROOT/03-configure-generate/ai-catapult-init/templates/dot-ai/execution/matrix-v1.1.schema.json" <<'PY' && ok 'published schema negative constraints' || bad 'published schema negative constraints'
import json,re,sys
s=json.load(open(sys.argv[1]));p=s['properties'];b=s['$defs']['binding']['properties']
assert p['upstream_authority']['additionalProperties'] is False
assert p['upstream_authority']['properties']['type']['const']=='git'
assert not re.fullmatch(p['upstream_authority']['properties']['url']['pattern'],'https://token@github.com/acme/root.git')
assert re.fullmatch(p['upstream_authority']['properties']['url']['pattern'],'https://gitlab.com/acme/root.git')
assert re.fullmatch(p['upstream_authority']['properties']['url']['pattern'],'https://dev.azure.com/acme/project/_git/root')
assert not re.fullmatch(b['path']['pattern'],'../escape')
assert not re.fullmatch(b['inherits_assets_from']['pattern'],'../escape')
assert not re.fullmatch(b['default_ref']['pattern'],'bad ref')
assert p['migration']['type']=='object' and p['exclusions']['type']=='array'
assert {x['if']['properties']['topology_type']['const']:x['then']['properties']['max_allowed_depth']['const'] for x in s['allOf']}=={'standalone':0,'umbrella':3}
PY
for field in profile_type profile_id version;do
 cp -R "$X/profiles" "$X/bad-profiles"
 python3 - "$X/bad-profiles/execution/default.json" "$field" <<'PY'
import json,sys
p=sys.argv[1];field=sys.argv[2];d=json.load(open(p));d[field]={'profile_type':'checkout','profile_id':'other','version':'2.0'}[field];json.dump(d,open(p,'w'))
PY
 expect "profile body $field skew rejects" fail python3 "$T" validate --profiles "$X/bad-profiles" --matrix "$X/v11.json"
 rm -rf "$X/bad-profiles"
done
cp -R "$X/profiles" "$X/bad-profiles";python3 - "$X/bad-profiles/execution/default.json" <<'PY'
import json,sys
p=sys.argv[1];d=json.load(open(p));d['settings']['host_selection']=['github','github'];json.dump(d,open(p,'w'))
PY
expect 'duplicate execution hosts reject' fail python3 "$T" validate --profiles "$X/bad-profiles" --matrix "$X/v11.json";rm -rf "$X/bad-profiles"
python3 - "$X/v10.json" "$X/bad.json" <<'PY'
import json,sys;d=json.load(open(sys.argv[1]));d.pop('upstream_authority');json.dump(d,open(sys.argv[2],'w'))
PY
expect 'malformed v1.0 rejects' fail "${V[@]}" --matrix "$X/bad.json"
python3 - "$X/v10.json" "$X/bad.json" <<'PY'
import json,sys;d=json.load(open(sys.argv[1]));d['schema_version']='1.2';json.dump(d,open(sys.argv[2],'w'))
PY
expect 'unknown matrix version rejects' fail "${V[@]}" --matrix "$X/bad.json"
python3 - "$X/profiles/execution/default.json" <<'PY'
import json;p='$X/profiles/execution/default.json'
PY
cat > "$X/overrides/one.json" <<'J'
{"trust_domain":"escape"}
J
expect 'forbidden child override rejects' fail "${G[@]}" --matrix "$X/v11.json"
cat > "$X/overrides/one.json" <<'J'
{"host_selection":["lore"]}
J
expect 'Lore reserved and non-selectable' fail "${G[@]}" --matrix "$X/v11.json"
for f in .prototools .moon/workspace.yml .moon/toolchains.yml .moon/tasks/all.yml moon.yml;do [ -f "$ROOT/$f" ]&&ok "Moon file $f"||bad "Moon file $f";done
grep -q 'moon = "2.4.3"' "$ROOT/.prototools"&&grep -q 'proto = "0.58.2"' "$ROOT/.prototools"&&ok 'exact pins'||bad 'exact pins'
printf '\n%d passed; %d failed\n' "$P" "$F";[ $F -eq 0 ]
