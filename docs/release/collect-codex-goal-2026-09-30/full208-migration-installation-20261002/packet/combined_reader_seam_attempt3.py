"""Finite authenticated reads using the unchanged existing populated UAT facts.

No source rows, financial fixture, operational run, approval or dispatch is added.
An absent approval probe is explicitly a negative identity check, never a primary
receipt UUID or evidence of a not_materialized successor.
"""
import json
import time
import uuid


def run(replay, target, evidence, case):
    claims = {'sub': replay.UID, 'session_id': replay.SID, 'role': 'authenticated',
              'aal': 'aal1', 'exp': int(time.time()) + 3600}
    auth = "begin;set local role authenticated;select set_config('request.jwt.claims'," + replay.quoted(json.dumps(claims)) + ",true);"
    observations = {}

    def read(name, sql):
        value = json.loads(target.sql(auth + sql + ';commit;', label='combined current authenticated reader ' + name).stdout.strip().splitlines()[-1])
        observations[name] = value
        return value

    current = replay.fingerprints(target, evidence['preserved_columns'])
    facts = target.json("select jsonb_build_object('runs',(select count(*)from collect_receipt_operations.runs),'starts',(select count(*)from collect_receipt_operations.requests where action='begin_run'),'worker_receipts',(select count(*)from collect_ops.receipt_worker_receipts),'approvals',(select count(*)from collect_receipt_successors.approvals),'primary_receipts',(select count(*)from collect_hybrid.sms_notification_outbox));")
    case('combined reader fixture remains the original populated source without new run approval or worker receipt',
         facts == {'runs': 0, 'starts': 0, 'worker_receipts': 0, 'approvals': 0, 'primary_receipts': 2})
    starts = read('operational-starts', 'select public.admin_list_receipt_operation_starts_v1(20,null,null)')
    case('full current graph authenticates redacted empty operational starts',
         starts['scope'] == 'rw_receipt_operational_history' and starts['section'] == 'starts'
         and starts['rows'] == [] and starts['next_cursor'] is None and starts['history_complete'] is False
         and starts['financial_action'] is False and starts['send_action'] is False)
    # This UUID is an existing transaction, explicitly verified not to be a run.
    unavailable = read('absent-operational-run', 'select public.admin_get_receipt_operation_run_v1(' + replay.quoted(replay.RAW) + ')')
    case('existing transaction UUID remains explicitly unavailable as an operational run',
         unavailable['status'] == 'unavailable' and unavailable['run'] is None
         and unavailable['historical_config'] is None and unavailable['completion'] is None
         and unavailable['quota_usage'] is None)
    for section in ('events', 'backlog_results', 'budget_refusals', 'reservations'):
        value = read('absent-run-' + section, 'select public.admin_list_receipt_operation_evidence_v1(' +
                     replay.quoted(replay.RAW) + ',' + replay.quoted(section) + ',20,null,null)')
        case('full current ' + section + ' reader keeps unavailable run evidence empty',
             value['status'] == 'unavailable' and value['section'] == section and value['rows'] == []
             and value['next_cursor'] is None and value['history_complete'] is False
             and value['financial_action'] is False and value['send_action'] is False)
    health = read('worker-health', 'select public.admin_get_receipt_exception_worker_health_v1()')
    case('full current worker health remains inactive and observation incomplete after700 adapters',
         health['state'] == 'inactive' and health['enabled'] is False and health['last_request_id'] is None
         and health['source_scan_complete'] is False and health['financial_action'] is False
         and health['send_action'] is False and health['external_send'] is False)
    #440 final source must be frozen before this module is used. No approval
    # exists in the unchanged fixture: generate only a query identifier and
    # verify its absence. It is never inserted or used as a primary receipt.
    approval_id = str(uuid.uuid4())
    case('negative approval query identifier has no existing approval or primary receipt',
         target.scalar('select not exists(select 1 from collect_receipt_successors.approvals where id=' +
                       replay.quoted(approval_id) + ')and not exists(select 1 from collect_hybrid.sms_notification_outbox where id=' +
                       replay.quoted(approval_id) + ');') == 't')
    email_identity = target.scalar('select collect_admin_access.email_identity(' + replay.quoted(replay.UID) + ');')
    case('retained ordinary fixture lacks current email-owner identity required by successor reads', email_identity == 'f')
    execution_sql = 'select public.admin_get_receipt_successor_execution_v4(' + replay.quoted(approval_id) + ')'
    execution_denial = target.sql(auth + execution_sql + ';commit;', check=False,
                                 label='combined current authenticated reader absent-approval-execution-v4')
    expected_error = 'ERROR:  42501: receipt_action_current_email_owner_required'
    case('full current v4 reader denies the retained phone fixture before approval inspection',
         execution_denial.returncode != 0 and expected_error in execution_denial.stderr)
    observations['absent-approval-execution-v4'] = {
        'result_kind': 'denied', 'actual_psql_exit_code': execution_denial.returncode,
        'sqlstate': '42501', 'error_message': 'receipt_action_current_email_owner_required',
        'actual_stdout': execution_denial.stdout, 'actual_stderr': execution_denial.stderr,
        'unchanged_fixture_email_identity': email_identity, 'rpc_response': None,
        'unavailable_response_claimed': False, 'not_materialized_claimed': False,
    }
    case('bounded combined current read seam preserves all18 financial receipt Auth and approval projections',
         current == replay.fingerprints(target, evidence['preserved_columns']))
    evidence['combined_reader_fixture_facts'] = facts
    evidence['absent_approval_probe'] = {'approval_id': approval_id, 'inserted': False, 'is_primary_receipt_id': False,
                                        'result_kind': 'denied', 'sqlstate': '42501', 'error_message': 'receipt_action_current_email_owner_required',
                                        'unavailable_response_claimed': False, 'not_materialized_claimed': False}
    (target.report / 'combined-current-reader-observations.json').write_text(json.dumps(observations, indent=2) + '\n')
