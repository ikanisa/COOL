#!/usr/bin/env python3
"""Replay retained financial/privacy fixture consumers on an offline clone.

Own unique network-none target only; current schema, real admission APIs and
rollback assertions. Historical fixture branches are reported, never counted
as current acceptance. No provider/hosted/shared writes.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import types

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / 'scripts/tests/collect_current_release_upgrade_uat.py'
BASELINE = ROOT / '.cache/receipt-foundation-attempt8/schema-only.sql'
PREREQUISITE = ROOT / 'scripts/sql/receipt_transport_platform_prerequisites.sql'
CONSUMERS = {
    'scripts/hardening/receipt_v2_uat.sql': 'RECEIPT_V2_UAT_PASS:',
    'scripts/group_creation_journey_uat.sql': 'GROUP_CREATION_JOURNEY_UAT_PASS',
    'scripts/local_backend_privacy_lifecycle_uat.sql': 'LOCAL_BACKEND_PRIVACY_LIFECYCLE_PASS',
    'scripts/tests/attested_sms_finality_uat.sql': 'ATTESTED_SMS_BOUNDARY_UAT_PASS:',
}
CALLERS = ['scripts/hardening/rehearse_financial_sql.rb', 'scripts/qa/fullstack_database_sql.rb',
           'scripts/tests/production_upgrade_rehearsal.rb', 'scripts/tests/platform_admin_access_uat.rb',
           'scripts/group_creation_journey_uat.sh', 'scripts/local_backend_privacy_lifecycle_uat.sh', 'Makefile']
LOCAL_NET = ('alter function net.http_get(text,jsonb,jsonb,integer)security definer;'
             'alter function net.http_get(text,jsonb,jsonb,integer)set search_path=net;'
             'alter function net.http_post(text,jsonb,jsonb,jsonb,integer)security definer;'
             'alter function net.http_post(text,jsonb,jsonb,jsonb,integer)set search_path=net;')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report-dir',required=True)
    args=parser.parse_args()
    report=Path(args.report_dir).resolve()
    assert not report.exists(),'Fresh evidence directory required'
    report.mkdir(parents=True)
    capture=report/'captured-inputs'
    sources=[Path(__file__),HELPER,BASELINE,PREREQUISITE,*[ROOT/p for p in CONSUMERS],*[ROOT/p for p in CALLERS],*sorted((ROOT/'supabase/migrations').glob('*.sql'))]
    hashes={}
    for source in sources:
        body=source.read_bytes();rel=str(source.relative_to(ROOT));dest=capture/rel
        dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(body);hashes[rel]=sha(body)
    helper=types.ModuleType('captured_integrity_consumer_helper');helper.__file__=str(capture/HELPER.relative_to(ROOT))
    exec(compile(Path(helper.__file__).read_bytes(),helper.__file__,'exec'),helper.__dict__)
    helper.ROOT=ROOT;helper.BASELINE=capture/BASELINE.relative_to(ROOT)
    items=[]
    for source in sorted((capture/'supabase/migrations').glob('*.sql')):
        version,name=source.stem.split('_',1);body=source.read_bytes()
        items.append(dict(path='supabase/migrations/'+source.name,version=version,name=name,body=body.decode(),sha256=sha(body)))
    assert len(items)==len({i['version']for i in items})
    result=dict(status='running',started_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),source_hashes=hashes,
                target={},cases=[],scope='Retained active SQL consumers, real admission and preserved financial/privacy assertions in task-local normalized clone',
                hosted_written=False,shared_database_written=False,provider_called=False,final_acceptance=False)

    def save():
        (report/'result.json').write_text(json.dumps(result,indent=2)+'\n')

    save()
    try:
        platform,provenance=helper.platform_shape();result['platform_shape']=provenance
        (report/'platform-schema-only.sql').write_text(platform)
        with helper.Target(report,'consumers',result['target'])as target:
            target.sql(platform,label='captured row-free platform')
            for item in items:
                if item['version']=='20261001160000':
                    target.sql(LOCAL_NET,user='supabase_admin',label='local image trusted net metadata')
                    target.sql((capture/PREREQUISITE.relative_to(ROOT)).read_text(),user='supabase_admin',label='captured local private-reader prerequisite')
                    result['local_prerequisite']=dict(net_metadata_sha256=sha(LOCAL_NET.encode()),private_reader_sha256=hashes[str(PREREQUISITE.relative_to(ROOT))])
                helper.apply(target,[item],result['target'])
            assert int(target.scalar('select count(*)from supabase_migrations.schema_migrations;'))==len(items)
            def snapshot():
                names=['auth.users','auth.sessions','public.profiles','public.collections','public.collection_members',
                       'public.payments','public.ledger_entries','public.raw_payment_sms','public.parsed_payment_events',
                       'public.native_action_capabilities','public.audit_logs','public.receiver_mode_consents',
                       'collect_integrity.reservations','collect_integrity.phases','collect_integrity.completions']
                pairs=[]
                for name in names:
                    pairs.extend([helper.quoted(name),"(select md5(coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text),'[]')::text)from "+name+' t)'])
                return target.json('select jsonb_build_object('+','.join(pairs)+');')
            for source,marker in CONSUMERS.items():
                body=(capture/source).read_text();assert body.strip().lower().endswith('rollback;')
                before=snapshot()
                prefix="select set_config('collect.local_receipt_uat','clean-replay-current',false);select set_config('collect.recovery_drill','production-archive-v1',false);"
                run=target.sql(prefix+body,check=False,label='retained current fixture '+source)
                log=report/(Path(source).stem+'.log');log.write_text(run.stdout+run.stderr)
                after=snapshot()
                passed=run.returncode==0 and marker in run.stdout and before==after
                row=dict(source=source,source_sha256=hashes[source],status='pass'if passed else 'fail',exit_code=run.returncode,
                         marker_found=marker in run.stdout,rollback_snapshot_unchanged=before==after,log=log.name,log_sha256=sha(log.read_bytes()),
                         before=before,after=after,errors=run.stderr[-3500:]if run.returncode else '')
                result['cases'].append(row);save();print(('PASS 'if passed else 'FAIL ')+source,flush=True)
            result['status']='pass'if all(c['status']=='pass'for c in result['cases'])else 'fail'
    except Exception as error:
        result['status']='fail';result['error']=str(error);raise
    finally:
        result['source_drift']=[p for p,h in hashes.items()if not(ROOT/p).is_file()or sha((ROOT/p).read_bytes())!=h]
        result['source_current_at_finish']=not result['source_drift']
        result['completed_at']=datetime.datetime.now(datetime.timezone.utc).isoformat()
        if result['source_drift']:result['status']='stale-source'
        save()
    if result['status']!='pass':raise SystemExit(1)


if __name__=='__main__':main()
