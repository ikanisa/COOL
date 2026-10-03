from pathlib import Path
import hashlib,json
ROOT=Path.cwd();STAGE=ROOT/'.cache/receipt-full-candidate-rehearsal-20261002';PRIOR=ROOT/'docs/release/rapid-completion-2026-10-02/ordinary-current201-attempt1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
manifest=json.loads((PRIOR/'ROOT_MANIFEST.json').read_text())['sha256']
result=json.loads((PRIOR/'result.json').read_text());execution=json.loads((PRIOR/'root-command/execution.json').read_text());validation=json.loads((PRIOR/'ROOT_VALIDATION.json').read_text())
assert result['status']=='pass' and execution['exit_code']==0 and result['all_task_containers_removed'] and validation['task_containers_removed']
assert len(result['source_inventory'])==201 and len(result['cases'])==36
assert sum(len(v['migrations'])for v in result['phases'].values())==402
assert validation['result_sha256']==sha(PRIOR/'result.json') and validation['execution_sha256']==sha(PRIOR/'root-command/execution.json')
checked={}
for item in result['source_inventory']:
 rel='captured-migrations/'+Path(item['path']).name
 assert sha(PRIOR/rel)==item['sha256']==manifest[rel]==execution['source_bindings'][item['path']]
 checked[rel]=item['sha256']
for canonical,retained in [('scripts/tests/current_ordinary_installer_rehearsal.py','current_ordinary_installer_rehearsal.py'),('scripts/tests/collect_current_release_upgrade_uat.py','collect_current_release_upgrade_uat.py'),('scripts/sql/receipt_transport_platform_prerequisites.sql','receipt_transport_platform_prerequisites.sql')]:
 assert sha(ROOT/canonical)==sha(PRIOR/retained)==manifest[retained]==execution['source_bindings'][canonical]
 checked[retained]=sha(PRIOR/retained)
for path,digest in execution['tools'].items():assert sha(Path(path))==digest
for phase,data in result['phases'].items():
 assert data['status']=='pass' and data['task_container_removed'] and data['ordinary_installer']['superuser'] is False
 assert data['scheduler_readback']=={'cron':'off','net':'0','history':0}
 assert all(m['status']=='pass' and m['actual_installer_authority']['superuser'] is False for m in data['migrations'])
assert result['populated_predecessor_fingerprints']==result['populated_after_upgrade_fingerprints'] and len(result['preserved_columns'])==18 and len(result['config_columns'])==7
baseline=ROOT/'.cache/receipt-foundation-attempt8/schema-only.sql';assert sha(baseline)==result['platform_bootstrap']['retained_dump_sha256']
platform=PRIOR/'platform-bootstrap.sql';assert sha(platform)==result['platform_bootstrap']['extracted_platform_sha256']==manifest['platform-bootstrap.sql']
record={'status':'verified_read_only','prior_root_manifest_sha256':sha(PRIOR/'ROOT_MANIFEST.json'),'prior_result_sha256':sha(PRIOR/'result.json'),'prior_validation_sha256':sha(PRIOR/'ROOT_VALIDATION.json'),'prior_execution_sha256':sha(PRIOR/'root-command/execution.json'),'exact_checked_members':checked,'checked_member_count':len(checked),'tools':execution['tools'],'preserved_projection_count':18,'config_projection_count':7,'prior_applications':402,'prior_checks':36,'platform_baseline_sha256':sha(baseline),'platform_bootstrap_sha256':sha(platform),'target_created':False,'current_candidate_unfrozen':True}
(STAGE/'PRIOR_BINDINGS.json').write_text(json.dumps(record,indent=2)+'\n');print(json.dumps({k:record[k]for k in ('status','checked_member_count','prior_applications','prior_checks','target_created')}))
