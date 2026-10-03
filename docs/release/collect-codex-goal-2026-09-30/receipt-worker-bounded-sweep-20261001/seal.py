#!/usr/bin/env python3
"""Seal only a completed passing staged query proof; never certify deployment."""
import datetime
import hashlib
import json
import pathlib
import shutil
import subprocess

STAGE = pathlib.Path(__file__).resolve().parent
sha = lambda b: hashlib.sha256(b).hexdigest()
proof = STAGE/'attempt5'
result = json.loads((proof/'result.json').read_text())
assert result['status'] == 'pass'
assert len(result['checks']) == 39 and all(c['passed'] for c in result['checks'])
assert result['sources_unchanged'] and result['python_unchanged']
assert result['target']['task_container_removed']
for path,digest in result['source_bindings'].items():
    assert sha(pathlib.Path(path).read_bytes()) == digest
packet = STAGE/'packet'
assert not packet.exists()
packet.mkdir()
for name in ['20261001210000_receipt_worker_bounded_sweep.sql','receipt_worker_bounded_sweep_uat.py','README.md','seal.py']:
    shutil.copy2(STAGE/name, packet/name)
shutil.copytree(proof, packet/'accepted-sql-attempt5')
rejections = []
for n in range(1,5):
    old = STAGE/('attempt'+str(n))
    receipt = json.loads((old/'result.json').read_text())
    assert receipt['status'] == 'failed' and receipt['target']['task_container_removed']
    saved = packet/'rejected-attempts'/old.name
    saved.mkdir(parents=True)
    for name in ['result.json','execution-binding.json','target-handle.json']:
        shutil.copy2(old/name, saved/name)
    log = old/'bounded_sweep/queries.log'
    raw = log.read_bytes()
    text = raw.decode()
    last = text.rfind('ERROR:')
    (saved/'failure-excerpt.txt').write_text(text[max(0,last-400):last+5000] if last >= 0 else text[-5400:])
    rejections.append(dict(attempt=old.name, raw_attempt=str(old), query_log_sha256=sha(raw),
                           error=receipt['error'], task_container_removed=True))
docker = pathlib.Path('/Volumes/PRO-G40/Applications/Docker.app/Contents/Resources/bin/docker')
for n in range(1,6):
    receipt = json.loads((STAGE/('attempt'+str(n))/'result.json').read_text())
    absent = subprocess.run([str(docker),'inspect','--format','{{.Id}}',receipt['target']['container_name']],capture_output=True,text=True)
    assert absent.returncode == 1 and ('no such object: '+receipt['target']['container_name']) in absent.stderr.lower()
validation = dict(status='pass', scope='local staged bounded source-sweep and evidence/latest query-cost slice',
                  checked_at=datetime.datetime.now(datetime.timezone.utc).isoformat(), accepted_attempt=5,
                  passing_checks=39, manifest_is_file_integrity_only=True,
                  migration_sha256=result['migration_sha256'], proof_result_sha256=sha((proof/'result.json').read_bytes()),
                  docker_cli_path=str(docker), docker_cli_sha256_at_seal=sha(docker.read_bytes()),
                  postgres_server=result['target']['guard']['server'],
                  image='public.ecr.aws/supabase/postgres:17.6.1.095',
                  image_id='sha256:35ebf7c6d3b77a430146b0a91974ed1fc14432b5741db4a3e41cd5f899b17f1a',
                  all_five_owned_targets_absent=True,
                  source_bindings_current=True, rejections=rejections,
                  canonical_source_written=False, hosted_written=False, sms_sent=False,
                  complete_retention=False, whole_current_candidate_replayed=False,
                  acceptance_limits=['177 unchanged captured fixture migrations plus 110000/120000/140000/150000 and staged210000',
                                     'fixture bootstrap locally normalized; new migration and changed-body checks actual NOSUPERUSER',
                                     '1100 genuine synthetic canonical postings; 2000 latest-query anchors explicitly installer fixtures',
                                     'one complete passing39 check execution; rejected preceding attempts not summed',
                                     'one-time historical backfill/index creation holds producer table locks; hosted duration/capacity unmeasured',
                                     'worker hot/cold maintenance/export/restore and total-count query costs remain separate'])
(packet/'acceptance.json').write_text(json.dumps(validation,indent=2)+'\n')
files = {}
for p in sorted(packet.rglob('*')):
    assert not p.is_symlink()
    if p.is_file():
        b = p.read_bytes()
        files[str(p.relative_to(packet))] = dict(bytes=len(b), sha256=sha(b), mode=oct(p.stat().st_mode & 0o777))
manifest = dict(kind='staged-receipt-worker-bounded-sweep-query-proof', file_count=len(files), files=files)
(packet/'MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
for rel,item in files.items():
    p = packet/rel
    assert sha(p.read_bytes()) == item['sha256'] and len(p.read_bytes()) == item['bytes']
print(json.dumps(dict(packet=str(packet),file_count=len(files),manifest_sha256=sha((packet/'MANIFEST.json').read_bytes()),
                     acceptance_sha256=sha((packet/'acceptance.json').read_bytes()),checks=39),indent=2))
