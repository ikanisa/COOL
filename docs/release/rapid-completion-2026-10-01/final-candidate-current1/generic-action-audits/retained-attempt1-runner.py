#!/usr/bin/env python3
"""Finite actual12-action/audit acceptance of the frozen185 local candidate."""
import sys
sys.dont_write_bytecode = True
from pathlib import Path
import datetime as dt
import hashlib
import json
import traceback

LIVE = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
FROZEN = Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/collect-final-local-candidate-20261001-current1')
PACKET = Path(__file__).resolve().parent
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
helpers = ['current_admin_query_benchmark_uat.py', 'current_generated_query_benchmark_uat.py',
    'data_correctness_sql_positive_history_uat.py', 'data_correctness_sql_uat.py',
    'staged_bundle_upgrade_uat.py', 'collect_current_release_upgrade_uat.py',
    'local_schema_uat.py', 'local_offline_verification.py', 'shadow_supervisor_uat.py']
for name in helpers:
    rel = Path('scripts/tests') / name
    if sha(LIVE / rel) != sha(FROZEN / rel):
        raise SystemExit('Helper differs from frozen candidate: ' + str(rel))
sys.path.insert(0, str(LIVE / 'scripts/tests'))
import current_admin_query_benchmark_uat as C
Q, D, P, U = C.Q, C.D, C.P, C.U
C.ROOT = FROZEN
RESULT = dict(kind='frozen185_generic_admin_actual_actions_and_audits', status='running',
    candidate=str(FROZEN), actions={}, checks=[], hosted_called=False, provider_called=False,
    shared_database_written=False, source_rows_copied=False, runtime_or_migrations_written=False)
REASON = 'Synthetic frozen candidate audited action reason'
CHECK_REASON = 'Synthetic independent checker audited approval reason'

def save():
    Q.save(PACKET / 'result.json', RESULT)

def check(name, ok, actual=None):
    RESULT['checks'].append(dict(name=name, status='pass' if ok else 'failed', actual=actual))
    save()
    if not ok:
        raise AssertionError(name + ': ' + json.dumps(actual, default=str))
    print('PASS ' + name, flush=True)

def value(db, body, uid=P.MAKER, sid=C.SID, service=False):
    authority = P.service() if service else P.actor(uid, sid)
    return D.scalar(db, 'begin;' + authority + 'select ' + body + ';commit;')

def deny(db, name, body, uid=P.MAKER, sid=C.SID, codes=None, service=False):
    before = D.scalar(db, 'select to_jsonb(count(*))from public.audit_logs;')
    authority = P.service() if service else P.actor(uid, sid)
    r = U.psql(db, '\\set VERBOSITY verbose\nbegin;' + authority + 'select ' + body + ';rollback;', False)
    (PACKET / (name + '.stdout')).write_text(r.stdout)
    (PACKET / (name + '.stderr')).write_text(r.stderr)
    code = None
    import re
    m = re.search(r'ERROR:\s+([0-9A-Z]{5}):', r.stderr)
    if m:
        code = m.group(1)
    after = D.scalar(db, 'select to_jsonb(count(*))from public.audit_logs;')
    check(name, r.returncode != 0 and before == after and (codes is None or code in codes),
          dict(exit=r.returncode, sqlstate=code, audit_before=before, audit_after=after))
    return dict(sqlstate=code, audit_delta=after-before)

def audit(db, endpoint, action, target, reason=REASON, actor=P.MAKER, entity=None, note_id=None):
    rows = D.scalar(db, "select coalesce(jsonb_agg(jsonb_build_object('actor',actor_user_id,'action',action," 
        "'entity_type',entity_type,'entity_id',entity_id,'metadata',metadata)order by id),'[]'::jsonb)"
        "from public.audit_logs where action=" + D.literal(action) + 'and entity_id=' + D.literal(target) + '::uuid;')
    ok = len(rows) == 1 and rows[0]['actor'] == actor and (entity is None or rows[0]['entity_type'] == entity)
    if note_id is not None:
        ok = ok and rows[0]['metadata'] == dict(note_id=note_id)
    else:
        ok = ok and rows[0]['metadata'].get('reason') == reason
    check(endpoint + ' exact durable attributed audit', ok, rows)
    RESULT['actions'][endpoint]['audit_rows'] = rows
    save()

def generic(db, endpoint, body, invalid, action, target=None, entity=None, reason=REASON, uid=P.MAKER, sid=C.SID):
    RESULT['actions'][endpoint] = dict(actual_public_call=body, actor=uid, current_session=sid)
    denied = deny(db, endpoint + '-unprivileged-denied', body, D.OUTSIDER, P.OUTSIDER_SID, ['42501'])
    invalid_denied = deny(db, endpoint + '-invalid-reason-denied', invalid, uid, sid)
    ack = value(db, body, uid, sid)
    check(endpoint + ' actual positive ACK', isinstance(ack, dict) and ack.get('ok') is True, ack)
    row = RESULT['actions'][endpoint]
    row.update(ack=ack, permission_denial=denied, invalid_reason_denial=invalid_denied)
    if callable(target):
        target = target(ack)
    audit(db, endpoint, action, target, reason=reason, actor=uid, entity=entity,
          note_id=ack.get('note_id') if endpoint == 'admin_record_operator_note' else None)
    return ack

def run(db):
    lit = D.literal
    U.psql(db, f"""begin;
      insert into public.admin_role_permissions(role_id,permission_name)
        select '{P.ROLE}',name from public.admin_permissions on conflict do nothing;
      update public.collections set is_platform_sponsored=true,visibility='public_approved',
        public_status='public_approved',archived_at=null where id='{D.NO_ROUTE}';
      update public.collections set public_status='public_requested' where id='{D.GROUP}';commit;""")
    P.seed_notification_catalog(db)
    make_group = lambda reason: ("public.admin_create_platform_public_group('Synthetic audited group','Synthetic private fixture',"
        "'ikimina',null,'Synthetic savings','Synthetic receiver','41259','mtn_momo'," + lit(reason) + ')')
    group = generic(db, 'admin_create_platform_public_group', make_group(REASON), make_group(''),
        'collection.platform_public.created', lambda a:a['collection_id'], 'collection')['collection_id']
    payee_create = lambda reason: f"public.admin_create_collect_payee('{D.NO_ROUTE}','Synthetic audited payee','41260','mtn_momo',{lit(reason)})"
    payee = generic(db, 'admin_create_collect_payee', payee_create(REASON), payee_create(''),
        'payee.official.created', lambda a:a['payee_id'], 'collection_receiver')['payee_id']
    edit = lambda reason: f"public.admin_update_collect_payee('{payee}','Synthetic edited payee',{lit(reason)})"
    generic(db, 'admin_update_collect_payee', edit(REASON), edit(''), 'payee.official.renamed', payee, 'collection_receiver')
    status = lambda reason:f"public.admin_set_collect_payee_status('{payee}',false,{lit(reason)})"
    generic(db, 'admin_set_collect_payee_status', status(REASON), status(''), 'payee.official.deactivated', payee, 'collection_receiver')
    check('payee edit/status preserves exact immutable payment route', D.scalar(db,
        f"select jsonb_build_object('label',label,'code',momo_number,'network',network,'active',is_active)from public.collection_receivers where id='{payee}';")
        == dict(label='Synthetic edited payee',code='41260',network='mtn_momo',active=False))
    active = lambda reason:f"public.admin_set_group_active('{group}',false,{lit(reason)})"
    generic(db, 'admin_set_group_active', active(REASON), active(''), 'collection.deactivated', group, 'collection')
    support = lambda reason:f"public.admin_update_collection_support_status('{D.GROUP}','public_approved',{lit(reason)})"
    generic(db, 'admin_update_collection_support_status', support(REASON), support(''), 'collection.support_status.updated', D.GROUP, 'collection')
    metadata = lambda reason:f"public.admin_update_platform_public_group_metadata('{group}','Synthetic changed metadata','Synthetic changed description','ikimina',null,'Synthetic changed savings','Synthetic receiver',{lit(reason)})"
    generic(db, 'admin_update_platform_public_group_metadata', metadata(REASON), metadata(''),
        'collection.platform_public.updated', group, 'collection')
    state = D.scalar(db,f"select jsonb_build_object('title',title,'visibility',visibility,'status',public_status,'archived',archived_at is not null)from public.collections where id='{group}';")
    check('metadata update preserves prior archived lifecycle',state == dict(title='Synthetic changed metadata',visibility='archived',status='archived',archived=True),state)
    note = lambda body:f"public.admin_record_operator_note('collection','{group}',{lit(body)})"
    note_ack = generic(db, 'admin_record_operator_note', note(REASON), note(''),
        'admin.operator_note.recorded', group, 'collection')
    check('operator note durable body/actor exact and audit minimizes body',D.scalar(db,
        f"select jsonb_build_object('body',body,'actor',created_by,'target',entity_id)from public.admin_notes where id='{note_ack['note_id']}';")
        == dict(body=REASON,actor=P.MAKER,target=group))

    # Genuine REVIEW input, actual maker/checker/service posting; no fabricated POSTED rows.
    row = dict(P.fixture_rows()[0], amount=5, transaction='SYNTH-FROZEN-GENERIC-AUDIT-RECON')
    U.psql(db,'begin;' + P.review_input_sql(row) + 'commit;')
    payment=row['id']
    propose=lambda reason:f"public.propose_payment_reconciliation_v2('{payment}',repeat('b',64),'SYNTH-FROZEN-GENERIC-AUDIT-RECON','2026-09-28T12:00:00Z',{lit(reason)})"
    ep='propose_payment_reconciliation_v2'
    RESULT['actions'][ep]=dict(actual_public_call=propose(REASON),actor=P.MAKER,current_session=P.MAKER_SID)
    RESULT['actions'][ep]['permission_denial']=deny(db,ep+'-unprivileged-denied',propose(REASON),D.OUTSIDER,P.OUTSIDER_SID,['42501'])
    RESULT['actions'][ep]['invalid_reason_denial']=deny(db,ep+'-invalid-reason-denied',propose(''),sid=P.MAKER_SID)
    review=value(db,propose(REASON),sid=P.MAKER_SID)
    check(ep+' actual positive exact review ID', isinstance(review,str) and len(review)==36,review)
    RESULT['actions'][ep]['ack']=review
    audit(db,ep,'reconciliation.proposed',payment,entity='payment')
    check('propose exact replay retains one immutable review/audit',value(db,propose(REASON),sid=P.MAKER_SID)==review)
    finalize=f"public.finalize_approved_reconciliation_v2('{review}')"
    ep='reconciliation-finalize'
    RESULT['actions'][ep]=dict(actual_public_call=finalize,service_role_only=True,
        browser_authorization_call=f"public.authorize_reconciliation_finalization_v2('{review}')",
        reason_contract='uses immutable maker/checker approved evidence; finalizer has no reason parameter')
    RESULT['actions'][ep]['permission_denial']=deny(db,ep+'-authenticated-direct-denied',finalize,codes=['42501'])
    RESULT['actions'][ep]['unapproved_evidence_denial']=deny(db,ep+'-unapproved-evidence-denied',finalize,service=True)
    approve=lambda reason:f"public.approve_payment_reconciliation_v2('{review}',{lit(reason)})"
    ep='approve_payment_reconciliation_v2'
    RESULT['actions'][ep]=dict(actual_public_call=approve(CHECK_REASON),actor=P.CHECKER,current_session=P.CHECKER_SID)
    RESULT['actions'][ep]['permission_denial']=deny(db,ep+'-unprivileged-denied',approve(CHECK_REASON),D.OUTSIDER,P.OUTSIDER_SID,['42501'])
    RESULT['actions'][ep]['invalid_reason_denial']=deny(db,ep+'-invalid-reason-denied',approve(''),P.CHECKER,P.CHECKER_SID)
    deny(db,ep+'-maker-self-approval-denied',approve(CHECK_REASON),P.MAKER,P.MAKER_SID,['22023'])
    ack=value(db,approve(CHECK_REASON),P.CHECKER,P.CHECKER_SID)
    check(ep+' actual checker positive ACK',ack is True,ack)
    RESULT['actions'][ep]['ack']=ack
    audit(db,ep,'reconciliation.approved',payment,reason=CHECK_REASON,actor=P.CHECKER,entity='payment')
    authorize=value(db,f"public.authorize_reconciliation_finalization_v2('{review}')",P.CHECKER,P.CHECKER_SID)
    check('current checker authorizes Edge finalization of exact approved review',authorize is True,authorize)
    RESULT['actions']['reconciliation-finalize']['authorization_ack']=authorize
    ack=value(db,finalize,service=True)
    check('reconciliation-finalize actual genuine posting ACK', isinstance(ack,dict) and ack.get('review_id')==review
        and ack.get('payment_status')=='posted' and ack.get('evidence_level')=='independently_reconciled',ack)
    RESULT['actions']['reconciliation-finalize']['ack']=ack
    rows=D.scalar(db,"select coalesce(jsonb_agg(jsonb_build_object('actor',actor_user_id,'action',action,'entity_type',entity_type,'entity_id',entity_id,'metadata',metadata)),'[]'::jsonb)from public.audit_logs where action='reconciliation.finalized'and entity_id="+lit(payment)+'::uuid;')
    check('reconciliation-finalize exact durable payment/review audit',len(rows)==1 and rows[0]['entity_id']==payment
        and rows[0]['actor']==P.CHECKER and rows[0]['metadata']==dict(review_id=review,evidence_sha256='b'*64,
        proposed_by=P.MAKER,approved_by=P.CHECKER),rows)
    RESULT['actions']['reconciliation-finalize']['audit_rows']=rows
    before=P.financial(db)
    repeated=value(db,finalize,service=True)
    check('finalizer explicit replay returns same posted review with no duplicate financial/audit rows',
        repeated.get('review_id')==review and repeated.get('payment_id')==payment and repeated.get('replayed')is True
        and repeated.get('payment_status')=='posted' and P.financial(db)==before,repeated)
    posted=D.scalar(db,f"select jsonb_build_object('status',status,'amount',amount_rwf,'posted',posted_at is not null)from public.payments where id='{payment}';")
    check('genuine reconciliation posts exact five RWF',posted==dict(status='posted',amount=5,posted=True),posted)
    access=lambda reason:f"public.admin_set_user_access('{P.CHECKER}',false,{lit(reason)})"
    generic(db,'admin_set_user_access',access(REASON),access(''),'admin.access.deactivated',P.CHECKER,'profile')
    check('revoked target has no remaining active Admin grant',D.scalar(db,f"select to_jsonb(count(*))from public.admin_user_roles where user_id='{P.CHECKER}'and revoked_at is null;")==0)
    check('all12 declared generic action audited results present',len(RESULT['actions'])==12 and all(x.get('audit_rows') for x in RESULT['actions'].values()),list(RESULT['actions']))

def main():
    review=LIVE/'docs/release/rapid-completion-2026-10-01/ordinary-installer-current-resumption3-private-platform/result.json'
    current={str(p.relative_to(FROZEN)):sha(p)for p in sorted((FROZEN/'supabase/migrations').glob('*.sql'))}
    platform=FROZEN/'scripts/sql/receipt_transport_platform_prerequisites.sql'
    inputs=dict(current)
    for name in helpers:
        rel='scripts/tests/'+name; inputs[rel]=sha(FROZEN/rel)
    inputs['scripts/sql/receipt_transport_platform_prerequisites.sql']=sha(platform)
    RESULT.update(source_inputs=inputs,runner_sha256=sha(__file__),ordinary_receipt_sha256=sha(review))
    save()
    try:
        inventory=C.admit_receipt(json.loads(review.read_bytes()),current,str(platform.relative_to(FROZEN)),sha(platform))
        baseline,baseline_files=C.baseline_capture(current)
        for path in baseline_files:
            dest=PACKET/'baseline-receipts'/path.name;dest.parent.mkdir(exist_ok=True);dest.write_bytes(path.read_bytes())
        for rel,expected in inputs.items():
            path=FROZEN/rel;body=path.read_bytes();P.require(hashlib.sha256(body).hexdigest()==expected,dict(input_changed=rel))
            dest=PACKET/'runner-sources'/rel;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(body)
        stages=[(FROZEN/r['path'],(FROZEN/r['path']).read_bytes())for r in inventory if r['path']not in baseline]
        RESULT.update(baseline_schema_migration_count=len(baseline),appended_stage_count=len(stages),frozen_migration_count=len(current))
        U.SQL_LOG,U.CONCURRENCY_LOG=PACKET/'queries.log',PACKET/'concurrency.log'
        with C.private_clone(PACKET,RESULT,baseline,C.admit_platform_sql(platform.read_text()))as db:
            print('PRIVATE schema154 restored; appending frozen185 suffix31 as ordinary owner',flush=True)
            C.authority(db,PACKET,RESULT,stages)
            print('PRIVATE exact185 installed; current email-approved synthetic owner fixture ready',flush=True)
            actual=D.scalar(db,"select jsonb_build_object('count',count(*),'latest',max(version))from supabase_migrations.schema_migrations;")
            check('private exact frozen185 registry',actual==dict(count=185,latest=max(r['version']for r in inventory)),actual)
            run(db)
        RESULT['status']='pass'
    except Exception as error:
        RESULT.update(status='failed',failure=str(error),traceback=traceback.format_exc())
        print('FAIL '+str(error),flush=True)
    finally:
        U.SQL_LOG=U.CONCURRENCY_LOG=None
        RESULT['frozen_inputs_unchanged']=all(sha(FROZEN/rel)==h for rel,h in inputs.items())
        RESULT['completed_at']=dt.datetime.now(dt.timezone.utc).isoformat()
        RESULT['limits']=['Synthetic current email-approved SQL role/session claims, not signed JWT/email delivery.',
          'Private network-none local mechanics and durable audit readbacks; no provider/hosted/native/device authority.',
          'Actual service finalizer and authenticated authorizer exercised; Edge HTTP deployment not exercised.',
          'No new full migration replay: exact accepted schema154 plus31 frozen suffix stages.',
          'Finalizer reason is prior immutable maker/checker evidence; note audit stores ID instead of raw body.']
        if not RESULT['frozen_inputs_unchanged']:RESULT['status']='failed'
        save()
    return int(RESULT['status']!='pass')

if __name__=='__main__':
    raise SystemExit(main())
