"""One-use phase journal for a same-source, fenced configuration transition.

Adapter methods must independently verify actual state; action exceptions are
unknown outcomes, never authorizations to replay. This module does not reach a
service or mutate a deployment by itself.
"""
import fcntl,hashlib,json,os,stat
from pathlib import Path

PHASES=('plan','stop_scheduler','stop_startup','quiesce','drain','stop_storage','backup_restore','replace_edge','promote_app_env','start_storage','release','bind_startup','bind_scheduler','final')

def digest(raw):return hashlib.sha256(raw).hexdigest()
def encode(value):return (json.dumps(value,sort_keys=True,separators=(',',':'))+'\n').encode()

class Refused(RuntimeError):pass

class Journal:
 def __init__(self,root):
  self.root=Path(root).absolute();s=self.root.lstat()
  if self.root.resolve()!=self.root or not stat.S_ISDIR(s.st_mode) or s.st_uid!=os.getuid() or stat.S_IMODE(s.st_mode)!=0o700:raise Refused('protected_physical_journal_required')
  self.fd=os.open(self.root/'guard.lock',os.O_RDWR|os.O_CREAT|os.O_NOFOLLOW,0o600)
  ls=os.fstat(self.fd)
  if not stat.S_ISREG(ls.st_mode) or ls.st_uid!=os.getuid() or ls.st_nlink!=1 or stat.S_IMODE(ls.st_mode)!=0o600:raise Refused('protected_lock_required')
  try:fcntl.flock(self.fd,fcntl.LOCK_EX|fcntl.LOCK_NB)
  except BlockingIOError:os.close(self.fd);raise Refused('concurrent_guard_refused') from None
 def close(self):fcntl.flock(self.fd,fcntl.LOCK_UN);os.close(self.fd)
 def path(self,name):
  if not name or '/' in name or name in ('.','..'):raise Refused('invalid_journal_name')
  return self.root/name
 def exists(self,name):return os.path.lexists(self.path(name))
 def write(self,name,value):
  return self.write_raw(name,encode(value))
 def write_raw(self,name,raw):
  p=self.path(name);fd=os.open(p,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
  with os.fdopen(fd,'wb') as f:f.write(raw);f.flush();os.fsync(f.fileno())
  d=os.open(self.root,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
  try:os.fsync(d)
  finally:os.close(d)
  return digest(raw)
 def read(self,name):
  p=self.path(name);s=p.lstat()
  if not stat.S_ISREG(s.st_mode) or s.st_uid!=os.getuid() or s.st_nlink!=1 or stat.S_IMODE(s.st_mode)!=0o600:raise Refused('invalid_journal_entry')
  fd=os.open(p,os.O_RDONLY|os.O_NOFOLLOW)
  with os.fdopen(fd,'rb') as f:
   actual=os.fstat(f.fileno())
   if (actual.st_dev,actual.st_ino)!=(s.st_dev,s.st_ino):raise Refused('journal_entry_changed')
   raw=f.read(1024*1024+1)
  if len(raw)>1024*1024:raise Refused('journal_entry_too_large')
  return json.loads(raw)
 def pending(self):
  return [name for name in (*PHASES,'rollback') if self.exists(name+'-intent.json') and not self.exists(name+'-result.json')]

class Guard:
 def __init__(self,journal,adapter,manifest):
  self.journal=journal;self.adapter=adapter;self.manifest=manifest;self.manifest_hash=digest(encode(manifest))
  if not isinstance(manifest,dict) or manifest.get('format')!='collect.same-source.rotation-plan.v1':raise Refused('exact_manifest_required')
 def bind(self):
  j=self.journal
  if j.exists('bound-manifest.json'):
   if j.read('bound-manifest.json')!=self.manifest:raise Refused('manifest_changed')
  else:j.write('bound-manifest.json',self.manifest)
 def step(self,phase):
  j=self.journal
  if phase not in PHASES:raise Refused('unknown_phase')
  self.bind()
  if j.pending():raise Refused('unknown_outcome_reconcile_before_mutation')
  if j.exists('rollback-intent.json'):raise Refused('rollback_started')
  if j.exists(phase+'-intent.json') or j.exists(phase+'-result.json'):raise Refused('phase_is_one_use')
  prior=PHASES[:PHASES.index(phase)]
  if any(not j.exists(x+'-result.json') for x in prior):raise Refused('prior_phase_missing')
  self.adapter.verify(phase,self.manifest,j)
  intent={'format':'collect.same-source.phase-intent.v1','phase':phase,'plan_sha256':self.manifest_hash,'automatic_retry':False}
  j.write(phase+'-intent.json',intent)
  # The action may have taken effect even if the reply fails. Leave the durable
  # intent without a result and refuse all further mutations until reconciled.
  result=self.adapter.perform(phase,self.manifest,j)
  self.adapter.verify_result(phase,self.manifest,j,result)
  if not isinstance(result,dict) or result.get('complete') is not True:raise Refused('phase_completion_unconfirmed')
  j.write(phase+'-result.json',{'phase':phase,'plan_sha256':self.manifest_hash,**result})
  return {'phase':phase,'complete':True,'automatic_retry':False}
 def reconcile(self):
  if not self.journal.exists('bound-manifest.json') or self.journal.read('bound-manifest.json')!=self.manifest:raise Refused('bound_manifest_required')
  # Read-only; this never converts a pending intent to success and never retries.
  return {'pending':self.journal.pending(),'observed':self.adapter.observe(self.manifest,self.journal),'automatic_retry':False,'mutation':False}
 def rollback(self):
  j=self.journal;self.bind()
  pending=j.pending()
  if j.exists('rollback-intent.json') or j.exists('rollback-result.json'):raise Refused('rollback_is_one_use')
  if pending:
   # A rollback is never a retry. It is allowed only if the adapter can prove
   # the exact current identities and fencing despite the missing reply.
   observation=self.adapter.rollback_observation(pending,self.manifest,j)
   if not isinstance(observation,dict) or observation.get('rollback_safe') is not True:raise Refused('unknown_outcome_reconcile_before_rollback')
   j.write('rollback-reconciliation.json',{'pending':pending,'observed':observation,'automatic_retry':False})
  self.adapter.verify('rollback',self.manifest,j)
  j.write('rollback-intent.json',{'phase':'rollback','plan_sha256':self.manifest_hash,'automatic_retry':False})
  result=self.adapter.perform('rollback',self.manifest,j)
  self.adapter.verify_result('rollback',self.manifest,j,result)
  if not isinstance(result,dict) or result.get('complete') is not True:raise Refused('rollback_unconfirmed')
  j.write('rollback-result.json',{'phase':'rollback','plan_sha256':self.manifest_hash,**result})
  return {'phase':'rollback','complete':True,'automatic_retry':False}
