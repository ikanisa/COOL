#!/usr/bin/env python3
"""Exact retained source06 offline application-DDL compatibility rehearsal.

The predecessor runner is captured before execution. Its guarded targets have
no network, listener, published ports or scheduler execution. No shared/hosted
database URL is accepted. New narrow composition probes are rolled back.
"""
import datetime
import hashlib
import json
import pathlib
import sys
import types
import uuid

WORKSPACE = pathlib.Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
SOURCE = pathlib.Path('/Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20261001-source-06')
SOURCE_MARKER_SHA = '3dde2f704488a7a18d7d9f916f2451d76a8662bb79619b788d792706d11ba42f'
PACKET = pathlib.Path(__file__).resolve().parent
HELPER = 'scripts/tests/collect_current_release_upgrade_uat.py'
HELPER_SHA = '343cd3b21ac9629347b0080640891eac3bdacdea7df11752b129c5f943b6c33b'
BASELINE_SHA = '77262947961ac1a724195ea77bdb98088cebd30caecc625ded1d4a93ccbf6d3d'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def store(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def main():
    inputs = PACKET / 'captured-inputs'
    assert not inputs.exists(), 'Fresh packet inputs required; retain failed attempts separately'
    inputs.mkdir()
    marker_bytes = (SOURCE / '.collect-release-candidate.json').read_bytes()
    assert sha(marker_bytes) == SOURCE_MARKER_SHA
    marker = json.loads(marker_bytes)
    (inputs / 'source06-manifest.json').write_bytes(marker_bytes)
    sqls = sorted((SOURCE / 'supabase/migrations').glob('*.sql'))
    assert len(sqls) == 175 and len(marker['migration_versions']) == 175
    assert len({p.stem.split('_', 1)[0] for p in sqls}) == 175
    (inputs / 'sql').mkdir()
    inventory = []
    for p in sqls:
        relative = str(p.relative_to(SOURCE)); body = p.read_bytes()
        assert sha(body) == marker['source_files'][relative]['sha256'], relative
        (inputs / 'sql' / p.name).write_bytes(body)
        inventory.append({'path': relative, 'sha256': sha(body), 'bytes': len(body)})
    helper_bytes = (SOURCE / HELPER).read_bytes()
    assert sha(helper_bytes) == HELPER_SHA == marker['source_files'][HELPER]['sha256']
    (inputs / 'executed-helper.py').write_bytes(helper_bytes)
    runner_bytes = pathlib.Path(__file__).read_bytes()
    (inputs / 'executed-wrapper.py').write_bytes(runner_bytes)
    baseline = (WORKSPACE / '.cache/receipt-foundation-attempt8/schema-only.sql').read_bytes()
    assert sha(baseline) == BASELINE_SHA
    (inputs / 'row-free-platform-source.sql').write_bytes(baseline)
    hosted = (WORKSPACE / 'docs/release/collect-codex-goal-2026-09-30/hosted-readback/metadata.json').read_bytes()
    prior_packet = WORKSPACE / 'docs/release/collect-codex-goal-2026-09-30/current-full-upgrade-captured169'
    prior = json.loads((prior_packet / 'result.json').read_bytes())
    assert sha(hosted) == prior['hosted_boundary']['metadata_sha256']
    (inputs / 'hosted-read-only-metadata.json').write_bytes(hosted)
    old = {p['path']: p['sha256'] for p in prior['source_inventory']}
    assert len(old) == 169
    changed = [r for r in inventory if r['path'] in old and r['sha256'] != old[r['path']]]
    assert changed == []
    binding = {'kind': 'exact_retained_source06_application_ddl_compatibility',
        'source_root': str(SOURCE), 'source06_manifest_sha256': SOURCE_MARKER_SHA,
        'source06_classification': marker['capture_classification'], 'source06_approvals': marker['approvals'],
        'original_tree_or_production_acceptance': False, 'migration_count': len(inventory),
        'predecessor169_unchanged': True, 'added_after169': [r for r in inventory if r['path'] not in old],
        'executed_helper_path': HELPER, 'executed_helper_sha256': sha(helper_bytes),
        'executed_wrapper_sha256': sha(runner_bytes), 'helper_capture_before_execution': True,
        'hosted_metadata_sha256': sha(hosted), 'hosted_installed_application_bodies_verified': False,
        'row_free_schema153_sha256': sha(baseline), 'migrations': inventory,
        'runtime_not_attested': ['GoTrue/JWT/email provider', 'Storage blobs/service', 'managed-host installer privileges',
            'cron scheduling', 'native device/sender/carrier', 'production restore/deployment/approval']}
    store(PACKET / 'execution-binding.json', binding)
    # Execute exactly the retained module, never import the mutable checkout.
    module = types.ModuleType('source06_captured_upgrade_helper')
    module.__file__ = str(inputs / 'executed-helper.py')
    exec(compile(helper_bytes, module.__file__, 'exec'), module.__dict__)
    module.ROOT = SOURCE
    module.BASELINE = inputs / 'row-free-platform-source.sql'
    module.HOSTED = inputs / 'hosted-read-only-metadata.json'
    original_seed, original_verify = module.seed_populated, module.verify_populated

    def seed(target, evidence, case):
        original_seed(target, evidence, case)
        evidence['intent_projection_before'] = target.json("select jsonb_agg(to_jsonb(i)order by id)from public.payment_intents i where contribution_code like 'SYNTHETIC-%';")

    def verify(target, evidence, case, count):
        original_verify(target, evidence, case, count)
        narrow(target, evidence, case, module)

    module.seed_populated, module.verify_populated = seed, verify
    saved_argv = sys.argv
    sys.argv = [module.__file__, '--report-dir', str(PACKET / 'backend-uat')]
    try:
        module.main()
    finally:
        sys.argv = saved_argv
        end = {'source06_manifest_unchanged': sha((SOURCE / '.collect-release-candidate.json').read_bytes()) == SOURCE_MARKER_SHA,
            'all175_frozen_sql_unchanged': all(sha((SOURCE / r['path']).read_bytes()) == r['sha256'] for r in inventory),
            'frozen_helper_unchanged': sha((SOURCE / HELPER).read_bytes()) == HELPER_SHA,
            'wrapper_unchanged': pathlib.Path(__file__).read_bytes() == runner_bytes,
            'later_workspace_migrations_not_in_scope': [str(p.relative_to(WORKSPACE)) for p in sorted((WORKSPACE / 'supabase/migrations').glob('*.sql')) if str(p.relative_to(WORKSPACE)) not in {r['path'] for r in inventory}],
            'checked_at': datetime.datetime.now(datetime.timezone.utc).isoformat()}
        store(PACKET / 'end-source-readback.json', end)
        assert end['source06_manifest_unchanged'] and end['all175_frozen_sql_unchanged'] and end['frozen_helper_unchanged'] and end['wrapper_unchanged']


def narrow(target, evidence, case, m):
    q = m.quoted
    after_intents = target.json("select jsonb_agg(to_jsonb(i)order by id)from public.payment_intents i where contribution_code like 'SYNTHETIC-%';")
    expected = [dict(r, status='cancelled' if r['contribution_code'] == 'SYNTHETIC-UNVERIFIED' else r['status']) for r in evidence['intent_projection_before']]
    evidence['intent_projection_after'] = after_intents
    case('nineteenth predecessor projection retains every intent field except the documented incompatible status cancellation', after_intents == expected)
    domains = ['collect_receipt_actions', 'collect_operator_audit', 'collect_automation']
    case('final cancellation audit and policy tables have RLS and no direct API grants', target.scalar("select count(*)=15 and bool_and(c.relrowsecurity and not has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE'))from pg_class c cross join unnest(array['anon','authenticated','service_role'])r where c.relkind='r'and c.relnamespace in(%s);" % ','.join(q(s) + '::regnamespace' for s in domains)) == 't')
    case('final preparation private schemas and helpers expose no API usage or execution', target.scalar("select not exists(select 1 from pg_namespace n cross join unnest(array['anon','authenticated','service_role'])r where n.nspname in(%s)and has_schema_privilege(r,n.oid,'USAGE'))and not exists(select 1 from pg_proc p cross join unnest(array['anon','authenticated','service_role'])r where p.pronamespace in(%s)and has_function_privilege(r,p.oid,'EXECUTE'));" % (','.join(map(q, domains)), ','.join(q(s) + '::regnamespace' for s in domains))) == 't')
    owner_names = ['admin_inspect_unstarted_receipt_v1', 'admin_cancel_unstarted_receipt_v1', 'admin_get_unstarted_receipt_action_v1', 'admin_get_operator_entity_audit_v1', 'admin_get_unattended_operating_policy_v1', 'admin_configure_unattended_operating_policy_v1', 'admin_get_unattended_policy_request_v1']
    case('all seven new owner APIs grant authenticated execution and deny anon or service execution', target.scalar("select count(*)=7 and bool_and(has_function_privilege('authenticated',p.oid,'EXECUTE')and not has_function_privilege('anon',p.oid,'EXECUTE')and not has_function_privilege('service_role',p.oid,'EXECUTE'))from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in(%s);" % ','.join(map(q, owner_names))) == 't')
    service_names = ['gateway_device_key_v1', 'gateway_heartbeat_v1', 'gateway_reconcile_v1', 'gateway_callback_v1', 'gateway_dispatch_grant_v1', 'receipt_supervisor_key_v1', 'receipt_supervisor_observe_v1', 'receipt_supervisor_reconcile_v1']
    case('device and fixed Shadow service boundary remains narrow after the final chain', target.scalar("select count(*)=8 and bool_and(has_function_privilege('service_role',p.oid,'EXECUTE')and not has_function_privilege('anon',p.oid,'EXECUTE')and not has_function_privilege('authenticated',p.oid,'EXECUTE'))from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in(%s);" % ','.join(map(q, service_names))) == 't')
    claims = json.dumps({'sub': m.UID, 'session_id': m.SID, 'role': 'authenticated', 'aal': 'aal1'})
    auth = 'set local role authenticated;select set_config(\'request.jwt.claims\',' + q(claims) + ',true);'
    refused = target.sql('begin;' + auth + 'select public.admin_get_unattended_operating_policy_v1();commit;', check=False, label='legacy phone owner cannot acquire email-only policy authority')
    case('legacy approved phone owner still cannot acquire new email-only policy authority', refused.returncode != 0 and '42501:' in refused.stderr and 'operating_policy_current_email_owner_required' in refused.stderr)
    job = target.scalar("select id from collect_hybrid.sms_notification_outbox where payment_id='99780000-0000-4000-8000-000000050001';")
    req, policy_req, shadow_req = str(uuid.uuid4()), str(uuid.uuid4()), str(uuid.uuid4())
    # Every change below is isolated synthetic SQL and rolled back. The observed
    # action receipts therefore demonstrate execution, not a retained product run.
    setup = "begin;update auth.users set email='source06-owner@example.test',email_confirmed_at=clock_timestamp()where id=%s;insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)values(%s,'source06-owner@example.test',clock_timestamp()-interval '2 minutes','Synthetic source06 composition authority only');" % (q(m.UID), q(m.UID))
    body = """create function pg_temp.source06_composition()returns jsonb language plpgsql as $$
declare inspected jsonb;cancelled jsonb;replayed jsonb;lookup jsonb;receipt_audit jsonb;
policy_default jsonb;policy_receipt jsonb;policy_replay jsonb;policy_lookup jsonb;policy_current jsonb;
begun jsonb;sampled jsonb;finished jsonb;shadow_audit jsonb;run_id uuid;fence bigint;
runtime_denied boolean:=false;reveal_denied boolean:=false;retry_denied boolean:=false;live_denied boolean:=false;
begin
 inspected:=public.admin_inspect_unstarted_receipt_v1(%s);
 cancelled:=public.admin_cancel_unstarted_receipt_v1(%s,%s,1,'operator_cancelled');
 replayed:=public.admin_cancel_unstarted_receipt_v1(%s,%s,1,'operator_cancelled');
 lookup:=public.admin_get_unstarted_receipt_action_v1(%s);
 receipt_audit:=public.admin_get_operator_entity_audit_v1('receipt',%s);
 policy_default:=public.admin_get_unattended_operating_policy_v1();
 policy_receipt:=public.admin_configure_unattended_operating_policy_v1(%s,1,'Shadow',false,'operator_reviewed_configuration');
 policy_replay:=public.admin_configure_unattended_operating_policy_v1(%s,1,'Shadow',false,'operator_reviewed_configuration');
 policy_lookup:=public.admin_get_unattended_policy_request_v1(%s);
 policy_current:=public.admin_get_unattended_operating_policy_v1();
 begun:=public.begin_collect_shadow_run_v1(%s);run_id:=(begun->'run'->>'run_id')::uuid;fence:=(begun->'run'->>'fence_version')::bigint;
 sampled:=public.sample_collect_shadow_run_v1(run_id,fence);
 finished:=public.finish_collect_shadow_run_v1(run_id,fence);
 shadow_audit:=public.admin_get_operator_entity_audit_v1('shadow_run',run_id);
 begin perform public.admin_update_runtime_control_v1('feature_flags','{"key":"hybrid_sms_notifications"}'::jsonb,'{"enabled":false}'::jsonb,0,U&'\\FEFF\\FEFF');
 exception when sqlstate '22023'then if sqlerrm='runtime_control_revision_reason_required'then runtime_denied:=true;else raise;end if;end;
 begin perform public.admin_reveal_raw_sms(%s,U&'\\FEFF');
 exception when sqlstate 'P0001'then if sqlerrm='Reason is required'then reveal_denied:=true;else raise;end if;end;
 begin perform public.admin_retry_notification(%s,U&'\\FEFF');
 exception when sqlstate 'P0001'then if sqlerrm='Reason is required'then retry_denied:=true;else raise;end if;end;
 begin perform public.admin_configure_unattended_operating_policy_v1(%s,2,'Live',false,'operator_reviewed_configuration');
 exception when sqlstate '55000'then if sqlerrm='OPERATING_POLICY_LIVE_AUTHORITY_PENDING'then live_denied:=true;else raise;end if;end;
 return jsonb_build_object('inspection',inspected,'cancel',cancelled,'cancel_replay',replayed,'cancel_lookup',lookup,'receipt_audit',receipt_audit,
 'policy_default',policy_default,'policy_receipt',policy_receipt,'policy_replay',policy_replay,'policy_lookup',policy_lookup,'policy_current',policy_current,
 'shadow_begin',begun,'shadow_sample',sampled,'shadow_finish',finished,'shadow_audit',shadow_audit,
 'runtime_empty_reason_denied',runtime_denied,'reveal_empty_reason_denied',reveal_denied,'retry_empty_reason_denied',retry_denied,'live_authority_denied',live_denied);
end$$;""" % tuple(map(q, [job, req, job, req, job, req, job, policy_req, policy_req, policy_req, shadow_req, m.RAW, str(uuid.uuid4()), str(uuid.uuid4())]))
    # The local temporary invoker helper has no security-definer privilege.
    # Its result is logged as rolled-back synthetic evidence.
    query = setup + body + auth + 'select pg_temp.source06_composition();reset role;'
    assertions = """do $$declare rejected boolean;begin
 if not exists(select 1 from public.audit_logs where action='notification.sms.cancelled_unstarted'and actor_user_id=%s)then raise exception 'current cancel actor missing';end if;
 if not exists(select 1 from public.audit_logs where action='automation.operating_policy.configured'and actor_user_id=%s)then raise exception 'current policy actor missing';end if;
 begin update collect_receipt_actions.cancellations set request_id=request_id;raise exception 'cancellation unexpectedly mutable';exception when sqlstate '55000'then if sqlerrm<>'receipt_action_evidence_retained'then raise;end if;end;
 begin delete from collect_automation.policy_requests;raise exception 'policy unexpectedly mutable';exception when sqlstate '55000'then if sqlerrm<>'operating_policy_evidence_retained'then raise;end if;end;
 begin delete from collect_operator_audit.shadow_events;raise exception 'shadow audit unexpectedly mutable';exception when sqlstate '55000'then if sqlerrm<>'operator_audit_evidence_retained'then raise;end if;end;
 begin update collect_hybrid.sms_notification_outbox set message_body='Synthetic rejected tamper'where id=%s;raise exception 'payload unexpectedly mutable';exception when sqlstate 'P0001'then if sqlerrm<>'SMS notification payload and ledger snapshot are immutable'then raise;end if;end;
end$$;rollback;""" % tuple(map(q, [m.UID, m.UID, job]))
    result = target.sql(query + assertions, label='rolled-back email owner cancellation joined audit policy and manual Shadow composition')
    lines = [line for line in result.stdout.splitlines() if line.startswith('{"inspection"') or (line.startswith('{') and '"shadow_finish"' in line)]
    assert len(lines) == 1, result.stdout[-1000:]
    observed = json.loads(lines[0]); observed['fixture_execution_rolled_back'] = True
    store(target.report / 'observed-source06-narrow-composition.json', observed)
    case('upgraded preexisting primary exposes implicit revision1 and is eligible without financial reconstruction', observed['inspection']['receipt']['can_cancel'] and observed['inspection']['receipt']['revision'] == 1)
    case('actual cancel advances existing implicit revision1 to2 and original UUID replay is identical', observed['cancel']['revision'] == 2 and observed['cancel'] == observed['cancel_replay'] == observed['cancel_lookup']['receipt'])
    case('joined receipt audit returns the actual immutable cancellation UUID and revision', observed['receipt_audit']['status'] == 'available' and len(observed['receipt_audit']['rows']) == 1 and observed['receipt_audit']['rows'][0]['request_id'] == req and observed['receipt_audit']['rows'][0]['revision'] == 2)
    case('default policy remains Paused and approved future Shadow preference creates one recoverable immutable receipt', observed['policy_default']['configured_mode'] == 'Paused' and observed['policy_default']['emergency_stop'] and observed['policy_receipt'] == observed['policy_replay'] == observed['policy_lookup']['receipt'] and observed['policy_current']['configured_mode'] == 'Shadow' and observed['policy_current']['revision'] == 2)
    case('stored preference never creates dispatch limits schedule approval or assisted send authority', observed['policy_current']['execution']['unattended_dispatch_available'] is False and observed['policy_current']['limits']['enforcement'] is False and all(v is None for k, v in observed['policy_current']['limits'].items() if k.endswith('_actions') or k.endswith('_sms')) and observed['live_authority_denied'])
    case('manual Shadow server sample and completion compose with three immutable joined audit events', observed['shadow_finish']['run']['status'] == 'completed' and len(observed['shadow_audit']['rows']) == 3 and {r['action'] for r in observed['shadow_audit']['rows']} == {'shadow.started', 'shadow.sampled', 'shadow.completed'})
    case('both final whitespace migrations refuse BOM-only reason before source or sensitive mutations', observed['runtime_empty_reason_denied'] and observed['reveal_empty_reason_denied'] and observed['retry_empty_reason_denied'])
    case('current public cancel and policy actor attribution plus all three private histories and primary payload reject mutation', result.returncode == 0)
    case('rolled-back narrow composition retains all18 original financial receipt Auth and approval projections', m.fingerprints(target, evidence['preserved_columns']) == evidence['populated_predecessor_fingerprints'])
    case('rolled-back narrow composition retains the nineteenth expected intent projection', target.json("select jsonb_agg(to_jsonb(i)order by id)from public.payment_intents i where contribution_code like 'SYNTHETIC-%';") == after_intents)
    case('rolled-back composition leaves no new requests runs arms attempts or policy head changes', target.scalar("select(select count(*)=0 from collect_receipt_actions.cancellations)and(select count(*)=0 from collect_automation.policy_requests)and(select configured_mode='Paused'and revision=1 and emergency_stop from collect_automation.operating_policy)and(select count(*)=0 from collect_operator_audit.shadow_events)and(select count(*)=0 from collect_security.shadow_supervisor_runs)and(select count(*)=0 from collect_gateway.dispatch_arms)and(select count(*)=0 from collect_hybrid.sms_notification_attempts);") == 't')
    evidence['narrow_composition'] = {'new_feature_matrix_repeated': False, 'execution_rolled_back': True,
        'original_primary_identity': job, 'request_ids': {'cancel': req, 'policy': policy_req, 'shadow': shadow_req},
        'checks': 'final grants/RLS; email authority; cancel/replay/audit attribution; future policy and fixed manual Shadow; whitespace refusals; 19 predecessor projections'}


if __name__ == '__main__':
    main()
