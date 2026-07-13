#!/usr/bin/env python3
"""Dual-read matrix contracts and crash-safe child binding projections."""
from __future__ import annotations
import argparse, hashlib, json, os, re, secrets, shutil, sys, time
from pathlib import Path, PurePosixPath
from typing import Any
try:import fcntl
except ImportError:fcntl=None
ID=re.compile(r'^[a-z0-9][a-z0-9-]{0,62}$'); VERSION=re.compile(r'^\d+\.\d+$'); REF=re.compile(r'^[A-Za-z0-9][A-Za-z0-9._/-]*$')
URL=re.compile(r'^(?:https://(?:github\.com|gitlab\.com)/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\.git)?|git@(?:github\.com|gitlab\.com):[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.git|https://dev\.azure\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/_git/[A-Za-z0-9_.-]+)$')
PROFILE_TYPES=('checkout','execution','toolchain','cas'); HOSTS={'github','ado','gitlab'}; OVERRIDE_KEYS={'runner_preference','host_selection','toolchain_tier'}
EXECUTION_BASE={'runner_preference','host_selection','hosted_fallback'}; EXECUTION_EXTENDED=EXECUTION_BASE|HOSTS|{'transient_retry'}
TOP_KEYS={'schema_version','topology_type','max_allowed_depth','current_depth','sync_strategy','upstream_authority','managed_repositories','inherited_assets','sync_status'}
TOP_OPTIONAL={'memory','migration','exclusions'}; V11_KEYS=TOP_KEYS|{'repository_id'}
V10_REPO={'path','depth','inherits_assets_from'}; V11_REPO=V10_REPO|{'repo_id','canonical_origin','canonical_upstream','default_ref','disposable','moon_project_id','dependencies','profile_refs'}

def load(path:Path)->Any:
 try:return json.loads(path.read_text(encoding='utf-8'))
 except (OSError,json.JSONDecodeError) as exc:raise ValueError(f'{path}: {exc}') from exc

def exact(obj:Any,required:set[str],optional:set[str]=set(),label='object')->None:
 if not isinstance(obj,dict):raise ValueError(f'{label} must be an object')
 missing=required-set(obj); extra=set(obj)-required-optional
 if missing or extra:raise ValueError(f'{label} fields missing={sorted(missing)} unknown={sorted(extra)}')

def safe_path(value:Any)->bool:
 if not isinstance(value,str) or not value:return False
 p=PurePosixPath(value);return not p.is_absolute() and '..' not in p.parts and '.' not in p.parts

def safe_source(value:Any)->bool:return value=='.' or safe_path(value)

def validate_url(value:Any,nullable=False)->None:
 if value is None and nullable:return
 if not isinstance(value,str) or not URL.fullmatch(value) or re.search(r'https://[^/@]+@',value):raise ValueError(f'unsafe canonical URL: {value!r}')

def validate_profile(path:Path,kind:str,ref:dict[str,Any])->dict[str,Any]:
 exact(ref,{'type','id','version'},label=f'{kind} profile ref')
 if ref['type']!=kind or not ID.fullmatch(ref['id']) or not VERSION.fullmatch(ref['version']):raise ValueError(f'invalid {kind} profile ref')
 body=load(path/kind/f"{ref['id']}.json"); exact(body,{'schema_version','profile_type','profile_id','version','settings'},label=f'{kind} profile')
 if body['schema_version']!='1.0' or body['profile_type']!=kind or body['profile_id']!=ref['id'] or body['version']!=ref['version'] or not isinstance(body['settings'],dict):raise ValueError(f'{kind} profile version/type skew')
 settings=body['settings']
 allowed={'checkout':{'history','disposable'},'toolchain':{'tier'},'cas':{'mode'}}.get(kind)
 if allowed is not None and set(settings)!=allowed:raise ValueError(f'{kind} profile settings unknown/missing')
 if kind=='checkout' and (settings['history'] not in {'full','shallow'} or not isinstance(settings['disposable'],bool)):raise ValueError('invalid checkout profile')
 if kind=='execution':
  if not EXECUTION_BASE<=set(settings) or not set(settings)<=EXECUTION_EXTENDED:raise ValueError('execution profile settings unknown/missing')
  if settings['runner_preference'] not in {'self-hosted','hosted'} or not isinstance(settings['hosted_fallback'],bool):raise ValueError('invalid execution profile')
  if not isinstance(settings['host_selection'],list) or not settings['host_selection'] or len(settings['host_selection'])!=len(set(settings['host_selection'])) or any(h not in HOSTS for h in settings['host_selection']):raise ValueError('Lore is reserved/unsupported and hosts must be explicitly supported without duplicates')
  extended=set(settings)-EXECUTION_BASE
  if extended:
   if 'transient_retry' not in settings or any(host not in settings for host in settings['host_selection']):raise ValueError('selected execution adapters and transient retry policy are required')
   retry=settings['transient_retry']
   if not isinstance(retry,dict) or set(retry)!={'max_retries','classes'} or retry.get('max_retries')!=1 or set(retry.get('classes',[]))!={'provider-timed-out','executor-incomplete-after-heartbeat'}:raise ValueError('invalid same-executor transient retry policy')
   protected={'release','publish','deployment','cas-write'}
   for host in settings['host_selection']:
    adapter=settings[host]
    if not isinstance(adapter,dict) or set(adapter.get('fallback_excluded_tasks',[]))!=protected or adapter.get('max_redispatch_count')!=0:raise ValueError(f'invalid protected fallback contract for {host}')
 if kind=='toolchain' and settings['tier'] not in {'managed','system','unsupported'}:raise ValueError('invalid toolchain profile')
 if kind=='cas' and settings['mode'] not in {'disabled','pull-only','protected-write'}:raise ValueError('invalid CAS profile')
 return body

def validate_base(matrix:dict[str,Any],version:str)->list[dict[str,Any]]:
 required=V11_KEYS if version=='1.1' else TOP_KEYS;exact(matrix,required,TOP_OPTIONAL,label=f'matrix {version}')
 topo=matrix['topology_type']; maximum=0 if topo=='standalone' else 3 if topo=='umbrella' else -1
 if maximum<0 or matrix['sync_strategy']!='physical-copy' or matrix['max_allowed_depth']!=maximum or not isinstance(matrix['current_depth'],int) or not 0<=matrix['current_depth']<=maximum:raise ValueError('invalid topology/depth')
 exact(matrix['upstream_authority'],{'type','url','ref'},label='upstream_authority');validate_url(matrix['upstream_authority']['url']);
 if matrix['upstream_authority']['type']!='git' or not REF.fullmatch(matrix['upstream_authority']['ref']):raise ValueError('invalid upstream authority')
 if not isinstance(matrix['inherited_assets'],list) or not isinstance(matrix['sync_status'],dict):raise ValueError('invalid inherited assets/sync status')
 if 'migration' in matrix and not isinstance(matrix['migration'],dict):raise ValueError('migration must be an object')
 if 'exclusions' in matrix and (not isinstance(matrix['exclusions'],list) or any(not safe_path(x) for x in matrix['exclusions'])):raise ValueError('exclusions must be safe relative paths')
 repos=matrix['managed_repositories']
 if not isinstance(repos,list):raise ValueError('managed_repositories must be an array')
 return repos

def validate_matrix(matrix:dict[str,Any],profiles:Path)->str:
 version=matrix.get('schema_version')
 if version not in {'1.0','1.1'}:raise ValueError('schema_version must be supported 1.0 or 1.1')
 repos=validate_base(matrix,version);ids=[];paths=[];moon=[]
 if version=='1.1' and (not isinstance(matrix['repository_id'],str) or not ID.fullmatch(matrix['repository_id'])):raise ValueError('invalid parent repository_id')
 for repo in repos:
  exact(repo,V11_REPO if version=='1.1' else V10_REPO,label='managed repository')
  path=repo['path'];paths.append(path)
  if not safe_path(path) or not safe_source(repo['inherits_assets_from']) or repo['depth']!=len(PurePosixPath(path).parts) or repo['depth']>matrix['max_allowed_depth']:raise ValueError(f'invalid path/depth/inheritance source: {path!r}')
  if version=='1.1':
   for key in ('repo_id','moon_project_id'):
    if not isinstance(repo[key],str) or not ID.fullmatch(repo[key]):raise ValueError(f'invalid {key}')
   validate_url(repo['canonical_origin']);validate_url(repo['canonical_upstream'],nullable=True)
   if not REF.fullmatch(repo['default_ref']) or not isinstance(repo['disposable'],bool):raise ValueError('invalid default ref/disposable')
   if not isinstance(repo['dependencies'],list) or len(repo['dependencies'])!=len(set(repo['dependencies'])):raise ValueError('invalid dependencies')
   exact(repo['profile_refs'],set(PROFILE_TYPES),label='profile_refs')
   for kind in PROFILE_TYPES:validate_profile(profiles,kind,repo['profile_refs'][kind])
   ids.append(repo['repo_id']);moon.append(repo['moon_project_id'])
 observed_depth=max((repo['depth'] for repo in repos),default=0)
 if matrix['current_depth']!=observed_depth:raise ValueError(f'current_depth must equal observed depth {observed_depth}')
 if len(paths)!=len(set(paths)) or len(ids)!=len(set(ids)) or len(moon)!=len(set(moon)):raise ValueError('duplicate path/repo_id/moon_project_id')
 if version=='1.1':
  known=set(ids);graph={r['repo_id']:r['dependencies'] for r in repos}
  if any(d not in known or d==rid for rid,deps in graph.items() for d in deps):raise ValueError('unknown/self dependency')
  visiting=set();done=set()
  def visit(node:str)->None:
   if node in visiting:raise ValueError('dependency cycle')
   if node in done:return
   visiting.add(node)
   for dep in graph[node]:visit(dep)
   visiting.remove(node);done.add(node)
  for node in graph:visit(node)
 return version

def validate_overrides(value:Any)->dict[str,Any]:
 if value is None:return {}
 exact(value,set(),OVERRIDE_KEYS,label='child overrides')
 if 'runner_preference' in value and value['runner_preference'] not in {'self-hosted','hosted'}:raise ValueError('invalid runner override')
 if 'host_selection' in value and (not isinstance(value['host_selection'],list) or len(value['host_selection'])!=len(set(value['host_selection'])) or any(h not in HOSTS for h in value['host_selection'])):raise ValueError('Lore is reserved and hosts cannot be duplicated')
 if 'toolchain_tier' in value and value['toolchain_tier'] not in {'managed','system','unsupported'}:raise ValueError('invalid toolchain override')
 return value

def canonical(obj:Any)->bytes:return (json.dumps(obj,indent=2,sort_keys=True)+'\n').encode()
def inheritance_digest(matrix:dict[str,Any])->str:return hashlib.sha256(canonical(matrix['inherited_assets'])).hexdigest()

def render(matrix:dict[str,Any],profiles:Path,overrides:Path)->dict[str,bytes]:
 if validate_matrix(matrix,profiles)!='1.1':raise ValueError('projection requires matrix v1.1')
 files={};digest=inheritance_digest(matrix)
 for repo in matrix['managed_repositories']:
  override_path=overrides/f"{repo['repo_id']}.json"; local=validate_overrides(load(override_path) if override_path.exists() else {})
  projection={'schema_version':'1.0','projection_type':'parent-binding','parent_repo_id':matrix['repository_id'],'binding':{'repo_id':repo['repo_id'],'parent_path':repo['path'],'canonical_origin':repo['canonical_origin'],'canonical_upstream':repo['canonical_upstream'],'default_ref':repo['default_ref'],'disposable':repo['disposable'],'moon_project_id':repo['moon_project_id'],'dependencies':repo['dependencies'],'profile_refs':repo['profile_refs']},'profile_versions':{k:repo['profile_refs'][k]['version'] for k in PROFILE_TYPES},'inheritance_digest':digest,'local_overrides':local}
  raw=canonical(projection)
  if re.search(rb'(?i)(token|password|secret)',raw):raise ValueError('projection contains secret-like material')
  files[f"{repo['repo_id']}.json"]=raw
 manifest={'schema_version':'1.0','parent_repo_id':matrix['repository_id'],'inheritance_digest':digest,'files':{n:hashlib.sha256(b).hexdigest() for n,b in sorted(files.items())}}
 files['manifest.json']=canonical(manifest);return files

def pid_alive(pid:int)->bool:
 try:os.kill(pid,0);return True
 except OSError:return False

def publish_lock(lock:Path)->bool:
 token=secrets.token_hex(16);pending=lock.with_name(f'.{lock.name}.owner-{os.getpid()}-{token}')
 try:
  with pending.open('xb') as stream:
   stream.write(canonical({'pid':os.getpid(),'created_at':time.time(),'token':token}));stream.flush();os.fsync(stream.fileno())
  try:os.link(pending,lock)
  except FileExistsError:return False
  fsync_directory(lock.parent);return True
 finally:pending.unlink(missing_ok=True)

def lock_snapshot(lock:Path)->tuple[os.stat_result,dict[str,Any]|None]:
 try:
  before=lock.stat();data=load(lock);after=lock.stat()
  if (before.st_dev,before.st_ino)!=(after.st_dev,after.st_ino):return after,None
  exact(data,{'pid','created_at','token'},label='lock owner')
  if not isinstance(data['token'],str) or not data['token']:raise ValueError('invalid lock token')
  int(data['pid']);float(data['created_at']);return after,data
 except (FileNotFoundError,ValueError,TypeError,KeyError):
  try:return lock.stat(),None
  except FileNotFoundError:raise

def acquire_recovery_mutex(path:Path,timeout:float=2.0)->int:
 if fcntl is None:raise ValueError('recovery mutex requires POSIX advisory file locking on this platform')
 fd=os.open(path,os.O_CREAT|os.O_RDWR,0o600);deadline=time.monotonic()+timeout
 while True:
  try:fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB);return fd
  except BlockingIOError:
   if time.monotonic()>=deadline:os.close(fd);raise ValueError('timed out acquiring recovery mutex')
   time.sleep(.01)

def release_recovery_mutex(fd:int)->None:
 if fcntl is not None:fcntl.flock(fd,fcntl.LOCK_UN)
 os.close(fd)

def acquire(lock:Path,stale_after:float)->bool:
 mutex=lock.with_name(lock.name+'.recovery')
 while True:
  if publish_lock(lock):return True
  try:snapshot,owner=lock_snapshot(lock)
  except FileNotFoundError:continue
  if owner is not None and pid_alive(int(owner['pid'])):raise ValueError('projection lock is held by a live process')
  recovery_fd=acquire_recovery_mutex(mutex)
  try:
   try:current,current_owner=lock_snapshot(lock)
   except FileNotFoundError:continue
   same_inode=(snapshot.st_dev,snapshot.st_ino)==(current.st_dev,current.st_ino)
   same_token=owner is None or (current_owner is not None and owner['token']==current_owner['token'])
   if not same_inode or not same_token:continue
   if current_owner is not None and pid_alive(int(current_owner['pid'])):raise ValueError('projection lock is held by a live process')
   stale=lock.with_name(lock.name+f'.stale-{os.getpid()}-{secrets.token_hex(8)}')
   os.rename(lock,stale);fsync_directory(lock.parent);stale.unlink(missing_ok=True)
  finally:
   release_recovery_mutex(recovery_fd)

def recover(journal:Path)->None:
 if not journal.exists():return
 j=load(journal);exact(j,{'phase','output','temp','backup'},label='transaction journal')
 output=Path(j['output']);temp=Path(j['temp']);backup=Path(j['backup'])
 if j['phase'] not in {'prepared','backup_moved','promoted'}:raise ValueError('unknown transaction journal phase')
 if j['phase'] in {'prepared','backup_moved'} and not output.exists() and backup.exists():os.replace(backup,output)
 elif j['phase'] in {'backup_moved','promoted'} and output.exists():shutil.rmtree(backup,ignore_errors=True)
 else:
  if not output.exists() and backup.exists():os.replace(backup,output)
 shutil.rmtree(temp,ignore_errors=True);journal.unlink(missing_ok=True)

def write_journal(path:Path,phase:str,output:Path,temp:Path,backup:Path)->None:
 pending=path.with_name(path.name+f'.tmp-{os.getpid()}')
 with pending.open('wb') as stream:
  stream.write(canonical({'phase':phase,'output':str(output),'temp':str(temp),'backup':str(backup)}));stream.flush();os.fsync(stream.fileno())
 os.replace(pending,path)
 directory=os.open(path.parent,os.O_RDONLY)
 try:os.fsync(directory)
 finally:os.close(directory)

def fsync_directory(path:Path)->None:
 directory=os.open(path,os.O_RDONLY)
 try:os.fsync(directory)
 finally:os.close(directory)

def project(matrix_path:Path,profiles:Path,overrides:Path,output:Path,check:bool,fail_after:int|None,crash_at:str|None,stale_after:float,hold:float)->None:
 matrix=load(matrix_path);files=render(matrix,profiles,overrides)
 if check:
  actual={p.name:p.read_bytes() for p in output.glob('*.json')} if output.is_dir() else {}
  if actual!=files:raise ValueError('projection drift detected')
  return
 output.parent.mkdir(parents=True,exist_ok=True);base=output.parent/f'.{output.name}';lock=base.with_suffix('.lock');journal=base.with_suffix('.journal.json');temp=output.parent/f'.{output.name}.tmp-{os.getpid()}';backup=output.parent/f'.{output.name}.bak-{os.getpid()}';owned=False
 try:
  owned=acquire(lock,stale_after);recover(journal)
  if hold:time.sleep(hold)
  shutil.rmtree(temp,ignore_errors=True);temp.mkdir()
  for i,(name,raw) in enumerate(sorted(files.items()),1):
   with open(temp/name,'wb') as f:f.write(raw);f.flush();os.fsync(f.fileno())
   if fail_after and i>=fail_after:raise RuntimeError('injected render failure')
  write_journal(journal,'prepared',output,temp,backup)
  if crash_at=='after-intent':os._exit(85)
  if output.exists():os.replace(output,backup);fsync_directory(output.parent)
  write_journal(journal,'backup_moved',output,temp,backup)
  if crash_at=='after-backup':os._exit(86)
  os.replace(temp,output);fsync_directory(output.parent);write_journal(journal,'promoted',output,temp,backup)
  if crash_at=='after-promote':os._exit(87)
  shutil.rmtree(backup,ignore_errors=True);journal.unlink(missing_ok=True)
 finally:
  if not crash_at:shutil.rmtree(temp,ignore_errors=True)
  if owned and lock.exists():lock.unlink()

def main()->int:
 p=argparse.ArgumentParser();sub=p.add_subparsers(dest='command',required=True)
 for name in ('validate','project'):
  q=sub.add_parser(name);q.add_argument('--matrix',type=Path,required=True);q.add_argument('--profiles',type=Path,required=True)
  if name=='project':
   q.add_argument('--overrides',type=Path,required=True);q.add_argument('--output',type=Path,required=True);q.add_argument('--check',action='store_true');q.add_argument('--fail-after',type=int);q.add_argument('--crash-at',choices=['after-intent','after-backup','after-promote']);q.add_argument('--stale-after',type=float,default=300);q.add_argument('--hold-lock-seconds',type=float,default=0)
 a=p.parse_args()
 try:
  if a.command=='validate':validate_matrix(load(a.matrix),a.profiles)
  else:project(a.matrix,a.profiles,a.overrides,a.output,a.check,a.fail_after,a.crash_at,a.stale_after,a.hold_lock_seconds)
 except (ValueError,RuntimeError,OSError) as exc:print(f'matrix contract error: {exc}',file=sys.stderr);return 1
 return 0
if __name__=='__main__':raise SystemExit(main())
