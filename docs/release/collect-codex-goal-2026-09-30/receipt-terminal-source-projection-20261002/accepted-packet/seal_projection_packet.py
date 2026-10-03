#!/usr/bin/env python3
"""Seal only this owned stage; never promote canonical or mutate evidence."""
from pathlib import Path
import datetime,gzip,hashlib,json,shutil,stat,tarfile
S=Path(__file__).resolve().parent
R=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
P=S/'accepted-packet'
def digest(p):
 h=hashlib.sha256()
 with p.open('rb')as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
def save(p,v):p.write_text(json.dumps(v,indent=2)+'\n')
def main():
 assert not P.exists();P.mkdir()
 promote=json.loads((S/'promotion-manifest.json').read_text())
 for item in promote['changes']:
  p=S/item['staged_path'];assert digest(p)==item['new_sha256']
  canonical=R/item['path'];assert not canonical.exists()if item['old_sha256']is None else digest(canonical)==item['old_sha256']
  target=P/item['staged_path'];target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,target)
 shutil.copytree(S/'originals',P/'originals')
 for name in ['HANDOFF.md','CONTRACT_PROPOSAL.md','IMPLEMENTED_CONTRACT.md','UNREAD_MIRROR_CONTRACT.md','REUSED_SCANNER_MAP.md','reviewed-source-bindings.json','promotion-manifest.json','predecessor-bindings.json','verification.json','terminal-targets.json','tool-terminals.json','prepare_projection.py','source_projection.sql.in','receipt_source_projection_uat.py','projection_cases.py','ordinary_cron_scope_probe.py','seal_projection_packet.py']:
  shutil.copy2(S/name,P/name)
 for source in ['sql-attempt15/result.json','sql-attempt15/execution-binding.json','sql-attempt15/deep-original-source-live-sweep-explain.json','sql-attempt15/deep-telemetry-alert-seek-explain.json','sql-attempt15/unchanged-final-producer-bodies.json','sql-attempt15/actual-worker-original-lookup.json','sql-attempt15/actual-worker-transport-detail.json','sql-attempt15/actual-publication-gate-recovery.json','sql-attempt15/synthetic-vault-boundary.json','ordinary-cron-probe1/result.json','ordinary-cron-probe1/actual-ordinary-cron-owner-readback.json','ordinary-cron-probe1/actual-ordinary-cron-owner-api-probe.json']:
  p=P/source;p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(S/source,p)
 sources=sorted(p for p in S.rglob('*')if p.is_file()and P not in p.parents)
 assert not any(p.is_symlink()for p in sources)
 members={str(p.relative_to(S)):dict(sha256=digest(p),bytes=p.stat().st_size,mode=stat.S_IMODE(p.stat().st_mode))for p in sources}
 save(P/'raw-evidence-MANIFEST.json',members)
 with (P/'raw-evidence.tar.gz').open('wb')as raw:
  with gzip.GzipFile(filename='',mode='wb',fileobj=raw,compresslevel=1,mtime=0)as gz:
   with tarfile.open(fileobj=gz,mode='w',format=tarfile.PAX_FORMAT)as tf:
    for p in sources:
     info=tf.gettarinfo(str(p),arcname=str(p.relative_to(S)));info.uid=info.gid=0;info.uname=info.gname='';info.mtime=0
     with p.open('rb')as f:tf.addfile(info,f)
 assert all(digest(S/name)==v['sha256']for name,v in members.items())
 with tarfile.open(P/'raw-evidence.tar.gz','r:gz')as tf:
  archived={}
  for item in tf:
   assert item.isfile()and not Path(item.name).is_absolute()and '..'not in Path(item.name).parts
   f=tf.extractfile(item);h=hashlib.sha256();n=0
   for b in iter(lambda:f.read(1024*1024),b''):h.update(b);n+=len(b)
   assert item.name not in archived
   archived[item.name]=dict(sha256=h.hexdigest(),bytes=n,mode=item.mode)
 assert archived==members
 save(P/'archive-verification.json',dict(member_count=len(members),source_unchanged=True,actual_archive_verified=True,raw_member_manifest_sha256=digest(P/'raw-evidence-MANIFEST.json'),checked_at=datetime.datetime.now(datetime.timezone.utc).isoformat()))
 final={str(p.relative_to(P)):dict(sha256=digest(p),bytes=p.stat().st_size,mode=stat.S_IMODE(p.stat().st_mode))for p in sorted(P.rglob('*'))if p.is_file()}
 save(P/'MANIFEST.json',final)
 print(json.dumps(dict(packet=str(P),manifest_sha256=digest(P/'MANIFEST.json'),packet_members=len(final),raw_members=len(members),raw_archive_sha256=digest(P/'raw-evidence.tar.gz'),actual_archive_verified=True)))
if __name__=='__main__':main()
