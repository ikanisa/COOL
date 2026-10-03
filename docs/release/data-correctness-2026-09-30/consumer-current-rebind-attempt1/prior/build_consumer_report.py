#!/usr/bin/env python3
"""Build a source-bound audit index from a completed immutable client packet.

This reads source and test receipts only. It executes no tests, SQL or providers.
The index records source review separately from direct behavioral acceptance.
"""
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
packet = (ROOT / sys.argv[1]).resolve()
export = packet / 'source-export'
inputs = json.loads((packet / 'inputs.json').read_text())
validation_path = (ROOT / sys.argv[2]).resolve() if len(sys.argv) > 2 else packet / 'validation.json'
validation = json.loads(validation_path.read_text())
if validation_path != packet / 'validation.json':
    if (validation.get('source_packet') != str(packet.relative_to(ROOT))
            or not validation.get('original_failure_preserved')
            or validation.get('inputs_sha256') != hashlib.sha256((packet / 'inputs.json').read_bytes()).hexdigest()
            or validation.get('original_evidence_sha256', {}).get('validation.json') != hashlib.sha256((packet / 'validation.json').read_bytes()).hexdigest()):
        raise RuntimeError('A bound retained failure completion proof is required')
if validation['status'] != 'pass':
    raise RuntimeError('A passing immutable packet is required for this report')
if 'test/admin_roster_calendar_test.dart' not in inputs['declared_vm_tests']:
    raise RuntimeError('The current roster calendar cohort is required')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def files(names):
    return names.split()


families = [
    {
        'id': 'roster_calendar_and_ack',
        'files': files('lib/admin/core/admin_roster_models.dart lib/admin/core/admin_roster_import.dart'),
        'controls': 'Every roster expiry/created timestamp uses canonical real-calendar parsing within the existing String wire shape; staged ACK expiry must be a real instant exactly equal to the reviewed expiry before execution.',
        'why': 'The unchanged prior source accepted twelve malformed receipt expiry values and executed three reviews after an impossible or overprecision or non-String staged ACK normalized to the reviewed instant. Exact fields and hashes remain required.',
        'tests': files('test/admin_roster_calendar_test.dart'),
    },
    {
        'id': 'canonical_values',
        'files': files('lib/core/data/exact_json_values.dart lib/shared/models/collect_model_json_helpers.dart'),
        'controls': 'Exact interoperable integers; decimal text is bounded before conversion; immutable opaque identifiers; actual zoned calendar instants and UTC year bounds.',
        'why': 'Native and JavaScript must agree on financial values. Normalizing impossible dates or assigning device timezones to naive timestamps changes evidence.',
        'tests': files('test/data_correctness_contract_test.dart test/payment_json_integrity_test.dart'),
    },
    {
        'id': 'shared_domain',
        'files': files('lib/shared/models/collect_models.dart lib/shared/models/collect_profile_country_rules.dart'),
        'controls': 'Profile/group IDs and optional owner semantics; suggested amounts; group summaries; notification identity/date fields; roster disclosure and health count contracts.',
        'why': 'Forged IDs, truncated suggestions, unsafe counts and missing metadata must be rejected before they can become authorized client state.',
        'tests': files('test/data_correctness_contract_test.dart test/group_summary_integrity_test.dart test/group_summary_decoding_test.dart test/shared/member_data_authority_test.dart test/shared/collect_profile_country_rules_test.dart'),
    },
    {
        'id': 'payment_wire_aliases',
        'files': files('lib/shared/models/collect_payment_json.dart lib/shared/models/collect_payment_models.dart lib/shared/models/collect_summary_json.dart'),
        'controls': 'Positive exact RWF amounts and coherent aliases; explicit route/currency; no invented pending status; chronological intent lifetime; posting/payment identity precedence retained where fields describe distinct schemas.',
        'why': 'Alias conflicts must not select whichever amount is convenient. Historical expired intents remain valid history, while malformed lifetimes and unsupported payment routes cannot become actionable.',
        'tests': files('test/payment_json_integrity_test.dart test/payment_intent_decoding_test.dart test/payment_event_decoding_test.dart test/group_summary_integrity_test.dart'),
    },
    {
        'id': 'history_contract',
        'files': files('lib/shared/models/member_history_page.dart'),
        'controls': 'Unique IDs; exact count and full aggregates; loaded sums cannot exceed aggregates; coherent own IDs/flags; full-page equality; immutable cursor/revision/request/order checks.',
        'why': 'A recent window cannot prove a complete total or supported-group count. A forged own flag or repeated cursor must not inflate displayed financial totals.',
        'tests': files('test/data_correctness_contract_test.dart test/member_history_page_integrity_test.dart test/member_history_controller_integrity_test.dart test/shared/member_history_pagination_test.dart test/shared/rwanda_momo_history_test.dart'),
    },
    {
        'id': 'protected_cache',
        'files': files('lib/shared/repositories/collect_offline_cache.dart lib/shared/repositories/collect_repository_state.dart lib/core/security/protected_snapshot_store.dart'),
        'controls': 'Present array/map structure validated before legacy filters; all window IDs unique; missing aggregates/counts stay unknown; explicit zero preserved; real saved date; optional absent public owner round trips as null; damaged summary isolated.',
        'why': 'Invalid cached rows must not disappear into a misleading empty or zero result. Legacy migration must preserve valid Rwanda data without reviving foreign financial totals.',
        'tests': files('test/data_correctness_contract_test.dart test/payment_cache_integrity_test.dart test/payment_intent_cache_boundary_test.dart test/group_summary_cache_recovery_test.dart test/shared/collect_offline_cache_test.dart test/shared/rwanda_momo_history_test.dart'),
    },
    {
        'id': 'live_initial_and_scoped_reads',
        'files': files('lib/shared/repositories/collect_repository_live_reader.dart lib/shared/repositories/collect_repository.dart'),
        'controls': 'Actual SDK profile/group/summary/event identity validation and duplicate checks; requested intent/group match; exact counts; captured Bearer and sticky session checks after every initial-read await; old session cannot dispatch later stages.',
        'why': 'Blocking only final publication still allowed a retained old pipeline to make later calls under replacement authority. The prior immutable probe reproduced all ten replacement-stage cases and mixed token headers during a valid refresh.',
        'tests': files('test/shared/member_read_integrity_test.dart test/shared/member_data_authority_test.dart test/shared/contribution_intent_binding_test.dart'),
    },
    {
        'id': 'member_mutation_authority',
        'files': files('lib/shared/repositories/collect_repository_contribution_actions.dart lib/shared/repositories/collect_repository_helpers.dart lib/core/security/play_integrity_service.dart lib/core/security/phone_normalizer.dart lib/core/payments/rwanda_momo_number.dart'),
        'controls': 'Create group/profile update/group profile/join/promote/archive/transfer/notification pipelines retain immutable session authority; RPC and scoped fetch Bearer pinned; returned identity validated; capability timestamp strict; late native/verdict/reply cannot publish or advance old workflow.',
        'why': 'The same user ID after a new session, or A to B to A, is not permission to complete a departed operation. Returned profile, owner and membership fields must match the submitted operation.',
        'tests': files('test/shared/member_mutation_session_test.dart test/shared/contribution_intent_binding_test.dart test/core/play_integrity_service_test.dart test/shared/collect_repository_test.dart'),
    },
    {
        'id': 'provider_history_lifecycle',
        'files': files('lib/shared/repositories/collect_repository_history.dart lib/shared/repositories/collect_repository_providers.dart lib/shared/providers/collect_app_state.dart'),
        'controls': 'Repository replacement/session revision/profile/sync invalidates history, roster and health; late resolved and in-flight values are fenced; aggregate providers retain unknown; local complete-history shortcut is explicit fixture-only.',
        'why': 'Resolved provider values and retained controllers otherwise outlive the session that authorized them. Offline partial windows cannot establish a complete production total.',
        'tests': files('test/shared/member_data_authority_test.dart test/member_history_controller_integrity_test.dart test/features/member_data_unknown_states_test.dart'),
    },
    {
        'id': 'financial_inputs',
        'files': files('lib/shared/widgets/collect_financial_amount_entry.dart lib/core/payments/momo_ussd_launcher.dart lib/core/payments/momo_ussd_intent_guard.dart'),
        'controls': 'Decimal digits bounded before parsing; leading zeros and composing edits preserved; positive safe amount before native channel; preflight intent identity/amount/receiver/instant exact.',
        'why': 'JavaScript integer conversion can change large pasted input before validation. A contribution must launch only the exact reviewed current request.',
        'tests': files('test/core/rwf_amount_input_formatter_test.dart test/core/momo_ussd_amount_boundary_test.dart test/core/momo_ussd_intent_guard_test.dart'),
    },
    {
        'id': 'shared_link_storage',
        'files': files('lib/shared/repositories/pending_shared_group_intent_store.dart'),
        'controls': 'Real zoned captured instant, TTL, exact record/generation/owner/slug; local DateTime retains its instant when serialized UTC.',
        'why': 'An impossible calendar value previously normalized into a still-valid invitation retention window. The store must never silently extend or reinterpret an invitation.',
        'tests': files('test/shared/pending_shared_group_intent_store_test.dart'),
    },
    {
        'id': 'amount_date_display',
        'files': files('lib/core/utils/money_format.dart lib/core/utils/date_format.dart lib/shared/widgets/collect_financial_money.dart lib/shared/widgets/collect_financial_ledger.dart lib/shared/widgets/collect_financial_payments.dart'),
        'controls': 'Exact bounded money flows from validated DTOs; formatting preserves maximum positive/negative digits in default/en/fr/rw on VM and Chrome; display dates use the instant converted to local time.',
        'why': 'Correct wire values are insufficient if a formatter rounds them. Date rendering must use a real instant; local display conversion is source reviewed, not a claim of every physical-device timezone configuration.',
        'tests': files('test/core/money_format_test.dart test/payment_json_integrity_test.dart'),
    },
    {
        'id': 'unknown_total_and_roster_surfaces',
        'files': files('lib/features/home/home_screen.dart lib/features/home/home_public_groups_section.dart lib/features/collections/collections_screen.dart lib/features/activity/activity_screen.dart lib/features/ledger/ledger_screen.dart lib/features/collections/collection_detail_screen.dart lib/features/collections/collection_detail_timeline.dart lib/features/collections/collection_manage_screen.dart lib/features/payments/contribute_entry_screen.dart lib/features/status/group_members_screen.dart lib/shared/widgets/collect_group_cards.dart lib/shared/widgets/collect_group_card_editorial.dart lib/shared/widgets/collect_group_card_metrics.dart lib/shared/widgets/collect_history_footer.dart'),
        'controls': 'Absent summary/page stays unavailable; known zero remains zero; supported groups cannot become a complete empty set from a partial window; fresh roster loading/error removes retained IDs/amounts; all rows display validated DTO amounts/dates.',
        'why': 'A zero or no-activity message is a financial assertion. It requires explicit complete metadata. Retained AsyncData during authorization refresh is not current roster authority.',
        'tests': files('test/features/member_data_unknown_states_test.dart test/group_list_summary_availability_test.dart test/hardening/editorial_summary_availability_test.dart'),
    },
    {
        'id': 'contribution_workflow',
        'files': files('lib/features/payments/contribution_flow_screen.dart lib/features/profile/member_profile_gate.dart'),
        'controls': 'Sticky repository/session/profile captured across preparation, profile gate, preflight and native launch; stale reply/error cannot update the flow; provider subscription survives transient missing-group state.',
        'why': 'A departed session cannot authorize a payment later in the same mounted widget. Losing the subscription during Auth clearance also prevented a legitimate current session from recovering.',
        'tests': files('test/features/contribution_flow_session_test.dart test/shared/contribution_intent_binding_test.dart'),
    },
    {
        'id': 'other_member_hosts',
        'files': files('lib/features/collections/collection_create_screen.dart lib/features/collections/collection_create_widgets.dart lib/features/collections/group_profile_screen.dart lib/features/collections/group_profile_form_controls.dart lib/features/profile/profile_edit_screen.dart lib/features/profile/profile_edit_widgets.dart'),
        'controls': 'Source-reviewed hosts call corrected repository operations; they do not decode financial JSON or derive financial totals. Their repository data/authority boundaries are directly tested; these tests do not certify every host navigation/visual state.',
        'why': 'A source callsite and a repository proof are distinct evidence. Keep the exact lower-layer acceptance without claiming an unrun complete widget journey.',
        'tests': files('test/shared/member_mutation_session_test.dart'),
    },
    {
        'id': 'delegated_invitation',
        'files': files('lib/shared/repositories/collect_invitation_protection.dart lib/features/collections/share_screen.dart lib/features/collections/group_share_service.dart lib/features/collections/group_link_screen.dart lib/features/collections/group_invitation_transport.dart lib/shared/utils/collect_share_links.dart'),
        'controls': 'Invitation operations and save-result proof owned by asset worker; summary display source-reviewed unknown guard; exact current acceptance supplied separately.',
        'why': 'Invitation permission/session and external save-result semantics need their own accepted packet; the shared data gate must not infer them from compilation.',
        'tests': [],
        'acceptance': 'delegated_asset_packet_required',
    },
    {
        'id': 'delegated_runtime_controls_and_push',
        'files': files('lib/shared/repositories/runtime_control_contract.dart lib/core/notifications/collect_notification_service.dart lib/features/settings/settings_subscreens.dart lib/core/security/durable_sms_receipt.dart lib/core/security/sms_access_channel.dart'),
        'controls': 'Canonical timestamp reused by runtime receipts; preference revision/session and remote push owner/session/UUID/deep-link/minimal payload controls inspected; durable SMS receipt is storage identity/hash ACK, not settlement.',
        'why': 'Push payloads and receipts cannot become payment or ownership evidence. These dedicated behavior cohorts belong to root/current platform packets and are not executed by this data gate.',
        'tests': files('test/shared/notification_preference_runtime_test.dart test/core/notification_account_isolation_test.dart test/core/notification_registration_recovery_test.dart test/hardening/durable_sms_receipt_test.dart'),
        'acceptance': 'delegated_current_packet_required',
    },
    {
        'id': 'delegated_gateway_observations',
        'files': files('lib/gateway/gateway_platform.dart lib/gateway/gateway_app.dart'),
        'controls': 'Native observation snapshot requires explicit Boolean fields and integer counts in 0..100; missing or malformed status cannot become zero. Enrollment/reason are allowlisted; UI distinguishes callbacks from actual recipient delivery.',
        'why': 'Gateway callback counts are bounded operational observations, not financial settlement or handset delivery proof. Runtime compilation and dedicated native acceptance remain owned by root.',
        'tests': [],
        'acceptance': 'delegated_root_gateway_packet_required',
    },
]

if inputs.get('actual_sql_history_scope'):
    families.append({
        'id': 'actual_sql_history_receipt_bridge',
        'files': files('lib/shared/models/collect_models.dart lib/shared/models/collect_payment_models.dart lib/shared/models/member_history_page.dart'),
        'controls': 'Captured genuine public reconciliation SQL mechanics feed the production history/balance decoders in VM and real Chrome; every window, continuation, complete exact sum, ownership flag, real timestamp and zero/unknown count is checked.',
        'why': 'Independent fake JSON model cases cannot prove that actual server receipts are compatible. The same source-bound SQL JSON must preserve precision and semantics in both native Dart and JavaScript. Synthetic mechanical fixtures and any server failures remain separately labeled.',
        'tests': files('test/actual_member_history_sql_receipts_test.dart'),
    })
assigned = {}
for family in families:
    for name in family['files']:
        if not (export / name).is_file():
            raise RuntimeError('Missing reviewed input: ' + name)
        assigned.setdefault(name, []).append(family['id'])

discovery = json.loads((OUT / 'consumer-source-discovery.json').read_text())
discovered = {row['file'] for row in discovery['files']}
symbol = re.compile(r'\b(?:CollectionSummary|PaymentIntentModel|PaymentIntentDraft|Contribution|ParsedPaymentEvent|CollectMember|OwnerGroupHealth|NotificationEvent|MemberHistoryPage|formatRwf|formatMoneyMinor|formatCurrencyTotals|formatCollectDateTime|exactJsonInteger|exactJsonIdentifier|exactJsonTimestamp)\b|DateTime\.(?:parse|tryParse)|(?:int|double)\.(?:parse|tryParse)')
current_refs = {}
for path in sorted((export / 'lib').rglob('*.dart')):
    matches = [{'line': i, 'symbols': sorted(set(symbol.findall(line)))}
               for i, line in enumerate(path.read_text().splitlines(), 1)
               if symbol.search(line)]
    if matches:
        name = str(path.relative_to(export))
        current_refs[name] = matches

live_refs = {}
for path in sorted((ROOT / 'lib').rglob('*.dart')):
    matches = [{'line': i, 'symbols': sorted(set(symbol.findall(line)))}
               for i, line in enumerate(path.read_text().splitlines(), 1)
               if symbol.search(line)]
    if matches:
        live_refs[str(path.relative_to(ROOT))] = {
            'sha256': digest(path), 'references': matches,
            'in_accepted_export': path.relative_to(ROOT).as_posix() in current_refs,
            'acceptance': ('delegated_admin_new_source_requires_owner_packet'
                           if path.relative_to(ROOT).as_posix() not in current_refs
                           and path.relative_to(ROOT).as_posix().startswith('lib/admin/')
                           else 'existing_family_or_explicit_source_reference'),
        }

all_files = sorted(set(assigned) | discovered | set(current_refs))
rows = []
for name in all_files:
    path = export / name
    if not path.is_file():
        raise RuntimeError('Discovery file no longer exists in export: ' + name)
    scope = assigned.get(name, [])
    if scope:
        review = 'reviewed_contract_or_consumer'
    elif name.startswith('lib/admin/'):
        review = 'delegated_admin_current_inventory_and_acceptance_required'
    else:
        # Explicit remaining source references are presentation/catalog/router
        # context, not additional JSON decoders or complete financial aggregates.
        review = 'nonfinancial_static_presentation_or_routing_reference'
    rows.append({'file': name, 'sha256': digest(path), 'families': scope,
                 'review': review, 'references': current_refs.get(name, []),
                 'live_matches_export': (ROOT / name).is_file() and digest(ROOT / name) == digest(path)})

named = {name: validation[name]['named_results'] for name in ['vm', 'browser']}
sql_packet = OUT / 'sql154-attempt2'
sql_result = json.loads((sql_packet / 'result.json').read_text())
sql_scope = {
    'packet': str(sql_packet.relative_to(ROOT)),
    'result_sha256': digest(sql_packet / 'result.json'),
    'status': sql_result['status'],
    'passed': sum(row['status'] == 'pass' for row in sql_result['cases']),
    'failed': sum(row['status'] == 'failed' for row in sql_result['cases']),
    'installed_migrations': sql_result['source_guard']['count'],
    'latest': sql_result['source_guard']['latest'],
    'source_preserved': sql_result['all_source_tables_catalog_cron_preserved'],
    'disposable_database_removed': sql_result['isolated_database_removed'],
    'full_server_acceptance': False,
    'scope': 'Schema-only actual installed154 APIs; source/financial preservation, real intents/full counts, empty summaries/history, ownership and payer/attestation denials. No posted/confirmed/native capability fabrication.',
}
patch_packet = OUT / 'sql154-attempt4-candidate234000'
patch_result = json.loads((patch_packet / 'result.json').read_text())
if (patch_result['status'] != 'pass_scoped'
        or not patch_result['all_source_tables_catalog_cron_preserved']
        or not patch_result['isolated_database_removed']
        or not patch_result['source_inputs_unchanged']
        or any(row['status'] != 'pass' for row in patch_result['cases'])):
    raise RuntimeError('The accepted exact-request candidate packet is required')
patch_scope = {
    'packet': str(patch_packet.relative_to(ROOT)),
    'result_sha256': digest(patch_packet / 'result.json'),
    'passed': len(patch_result['cases']), 'failed': 0,
    'candidate': patch_result['candidate'],
    'candidate_sha256': patch_result['source_inputs']['supabase/migrations/20260930234000_exact_request_amounts.sql'],
    'source_preserved': True, 'disposable_database_removed': True,
    'scope': 'Actual baseline154 schema plus reviewed234000 in a disposable clone; exact intent/target/suggestion bounds, atomic migration refusal, preserved signature/body/grants and null/positive controls.',
    'installed_in_shared_or_hosted_database': False,
    'recorder_version': 'The dated packet binds its original recorder, not the subsequent stronger catalog recorder.',
    'full_server_acceptance': False,
}
cohorts = {}
for name in inputs['declared_vm_tests']:
    suffix = '/' + name
    cohorts[name] = {'declared': True, 'direct_named_vm_results': sum(
        str(row.get('source', '')).endswith(suffix) for row in named['vm']),
        'note': 'Widget runner events may name package:flutter_test; counts are not inferred for those events.'}

result = {
    'status': 'scoped_client_report_server_parity_pending',
    'whole_system_acceptance': False, 'sql_executed_here': False,
    'packet': str(packet.relative_to(ROOT)),
    'validation_sha256': digest(validation_path),
    'validation_path': str(validation_path.relative_to(ROOT)),
    'retained_original_validation_sha256': digest(packet / 'validation.json'),
    'inputs_sha256': digest(packet / 'inputs.json'),
    'source_file_count': len(inputs['source']),
    'consumer_file_count': len(rows), 'control_family_count': len(families),
    'vm': {k: validation['vm'][k] for k in ['passed', 'failed', 'errors', 'skipped', 'runner_completed_successfully']},
    'browser': {k: validation['browser'][k] for k in ['passed', 'failed', 'errors', 'skipped', 'runner_completed_successfully']},
    'current_source_acceptance': validation['current_source_acceptance'],
    'installed154_sql_scope': sql_scope,
    'exact_request_candidate_sql_scope': patch_scope,
    'actual_sql_history_client_bridge_scope': validation.get('actual_sql_history_scope'),
    'live_source_drift': validation['live_source_drift'],
    'current_source_reference_rebind': {
        'reference_files': live_refs,
        'added_references_since_accepted_export': sorted(set(live_refs) - set(current_refs)),
        'removed_references_since_accepted_export': sorted(set(current_refs) - set(live_refs)),
        'new_reference_acceptance_claimed': False,
        'owned_runtime_consumers_all_match_export': all(row['live_matches_export'] for row in rows if row['families']),
    },
    'families': families, 'files': rows, 'declared_vm_cohorts': cohorts,
    'remaining_gaps': [
        'Baseline154 SQL reproduced2 exact integer amount defects. Root234000 candidate mechanics passed80 checks in a disposable clone; installation/current-server alignment remains separate.',
        'A separate genuine reconciliation API synthetic fixture is approved for positive history/ties/filter counts/full sums and all money bounds. Its terminal packet and bridge to native/Chrome receipts remain required; synthetic mechanics do not certify provider/native/device settlement.',
        'The separate normal Admin/Auth browser packet must be bound to the final runtime and retained actual149 SQL/concurrency receipts.',
        'Delegated Admin investigation, invitation/save-result, preference/push/native and browser Auth packets must be bound individually; this data gate does not execute or certify their whole scope.',
        'The positive-history server receipt binds the reviewed13-stage/167-source snapshot. New staged sources require their exact root ordinary-owner proof and current generated-query benchmark integration; the dated13-stage proof is not promoted to that newer scope.',
    ],
}
if validation.get('actual_sql_history_scope'):
    history_scope = validation['actual_sql_history_scope']
    captured_sql_path = packet / 'actual-history-sql/result.json'
    captured_sql = json.loads(captured_sql_path.read_text())
    if digest(captured_sql_path) != history_scope['result_sha256']:
        raise RuntimeError('Accepted SQL bridge source result changed')
    result['current_positive_history_sql_scope'] = {
        'result_sha256': digest(captured_sql_path),
        'status': captured_sql['status'],
        'passed': sum(c['status'] == 'pass' for c in captured_sql['cases']),
        'failed': sum(c['status'] == 'failed' for c in captured_sql['cases']),
        'mode': captured_sql.get('mode'),
        'receipt_candidate': captured_sql.get('receipt_candidate'),
        'reviewed_stage_packet': captured_sql.get('reviewed_stage_packet'),
        'all_shared_tables_catalog_cron_preserved': captured_sql['all_source_tables_catalog_cron_preserved'],
        'disposable_databases_removed': captured_sql['isolated_database_removed'],
        'runner_inputs_unchanged': captured_sql['source_inputs_unchanged'],
        'recorder_sources_unchanged': captured_sql['recorder_sources_unchanged'],
        'provider_truth': False,
        'shared_or_hosted_installation_claimed': False,
        'retained_unsafe_scope': history_scope.get('retained_unsafe_scope'),
    }
    result['remaining_gaps'][1] = (
        'Current reviewed staged SQL positive history mechanics and captured native/Chrome receipt decoding are bound in this client packet. '
        'The SQL server packet status is ' + history_scope['server_result_status'] + ', with ' +
        str(len(history_scope['server_failed_cases'])) + ' declared server failures. '
        'Retained prior unsafe receipts remain historical failed-server evidence and are consumed only as negative decoder controls. '
        'Shared/hosted installation and independent provider/native/device settlement are separate acceptance.'
    )
    if captured_sql['status'] == 'pass_scoped' and not history_scope['server_failed_cases']:
        result['status'] = 'scoped_client_and_current_staged_sql_accepted_final_bindings_pending'
if validation['live_source_drift']:
    result['remaining_gaps'].append('Live source drift requires an exact final common rebind; this packet remains accepted only for its immutable inputs.')
(OUT / 'consumer-matrix.json').write_text(json.dumps(result, indent=2) + '\n')
lines = [
    '# Shared data correctness and member authority review', '',
    '## Evidence and scope', '',
    f'Immutable packet: `{result["packet"]}`. VM: **{result["vm"]["passed"]} passed**; actual Chrome: **{result["browser"]["passed"]} passed**. Neither runner reports a failure, error or skip. Full-lib analysis is captured in the packet.', '',
    f'The matrix indexes **{len(rows)} source files** and **{len(families)} control families**. It separates direct client tests, source-reviewed consumers, static presentation references and delegated acceptance. A symbol scan alone is not acceptance.', '',
    'Validation SHA-256: `' + result['validation_sha256'] + '`. Input manifest SHA-256: `' + result['inputs_sha256'] + '`.', '',
    'No SQL, provider, hosted or native operation is executed by this report or its data gate. Complete L15 closure still requires root current-server parity and final source bindings.', '',
    'Separate installed154 SQL packet: **' + str(sql_scope['passed']) + ' passes / ' + str(sql_scope['failed']) + ' failures**; result SHA-256 `' + sql_scope['result_sha256'] + '`. The two failures reproduce numeric contribution receipts above the exact JSON bound. Source and financial fingerprints were preserved and the clone removed. See `sql154-critical-review.md` for precise scope and posting/attestation boundaries.', '',
    'Exact-request candidate234000: **' + str(patch_scope['passed']) + ' passes /0 failures**; result SHA-256 `' + patch_scope['result_sha256'] + '`. This proves the reviewed patch only in a disposable154 clone, including atomic refusal for unsafe predecessors. It does not claim shared or hosted installation, positive history, or the later stronger recorder.', '',
    '## Corrections and reasons', '',
    '| Control family | Current control or correction | Why it is required | Evidence cohorts |',
    '| --- | --- | --- | --- |',
]
for family in families:
    lines.append('| ' + family['id'] + ' | ' + family['controls'] + ' | ' + family['why'] + ' | ' + ('; '.join('`' + x + '`' for x in family['tests']) or family.get('acceptance', 'source review')) + ' |')
lines += [
    '', '## Prior failure retention', '',
    '`immutable-attempt14-current-client` retains 696 passing VM tests and three errors: two positive legacy history fixtures lacked their explicit own-contribution flag; the gate omitted two static source-inspection inputs. The fixtures now describe their stated own totals and both inputs are declared/hash copied. Aggregate validation was retained.', '',
    '`immutable-attempt15-initial-read-prior` retains six existing passing integrity controls and eleven new failures on unchanged copied source and SDK inputs. Ten cases proved later read dispatch after replacement sessions or A to B to A; the valid same-session refresh control proved mixed captured/current Bearer headers. The corrected pipeline pins every read and checks the existing sticky session after each await; valid same-session refresh remains supported.', '',
    '`immutable-attempt17-roster-calendar-prior` retains eight passing controls and fifteen failures on unchanged copied source and SDK inputs. Twelve malformed expiry timestamps normalized into accepted receipts; three staged ACKs advanced review execution after impossible-calendar, overprecision or non-String expiry input. The canonical helper now rejects them before execution while retaining equivalent zoned positive ACKs.', '',
    'All earlier failed or interrupted packets remain separate. No failed packet is overwritten or represented as current acceptance.', '',
    '## Remaining acceptance boundaries', '',
]
if result['actual_sql_history_client_bridge_scope']:
    history = result['actual_sql_history_client_bridge_scope']
    lines += [
        'Actual SQL history receipt bridge: packet `' + history['source_packet'] + '`, result SHA-256 `' + history['result_sha256'] + '`. The client consumes the captured genuine API/trigger receipts, rather than rewritten examples. Every SQL artifact and copied define file is hashed in the client input manifest. Server status `' + history['server_result_status'] + '` and all declared failures remain visible; client decoder acceptance does not turn failed server precision cases into a pass.', '',
    ]
    accepted = result['current_positive_history_sql_scope']
    lines += [
        'Current staged positive-history mechanics: **' + str(accepted['passed']) + ' passes /' + str(accepted['failed']) + ' failures**, mode `' + str(accepted['mode']) + '`. The additive235 candidate and exact root-reviewed stage manifest are bound in the matrix. All shared tables/catalog/cron are preserved, clones removed and source/recorder inputs unchanged. This replaces the former positive-data acceptance gap while preserving all older failures as dated evidence.', '',
        'Calendar acceptance includes one-microsecond ACK disagreement and zoned same-microsecond controls at2026/0001/9999 on VM and Chrome. Historical-year fake-authority cases test exact parser/ACK instants; they do not claim that a server admits expired work.', '',
    ]
lines += ['- ' + gap for gap in result['remaining_gaps']]
lines += ['', 'Current live drift recorded by the gate: ' + (', '.join('`' + x + '`' for x in result['live_source_drift']) or 'none') + '.', '',
          '## Complete file index', '',
          'Each file hash, current source match, control family and exact source reference is recorded in `consumer-matrix.json`. Files without direct tests are not promoted to full interaction acceptance. Runtime design remains an adapter of the sole Revolut authority; this data report makes no visual-fidelity percentage claim.', '']
lines += [
    'A separate current-source symbol rebind records every present matching source file. New source references after the accepted export are: '
    + (', '.join('`' + name + '`' for name in result['current_source_reference_rebind']['added_references_since_accepted_export']) or 'none')
    + '. New delegated Admin files require their owner acceptance; they are not covered by the older data copy. All assigned runtime consumer hashes match the accepted export: '
    + str(result['current_source_reference_rebind']['owned_runtime_consumers_all_match_export']) + '.', '',
]
(OUT / 'critical-review.md').write_text('\n'.join(lines))
print(json.dumps({'consumer_files': len(rows), 'families': len(families), 'packet': result['packet'], 'matrix_sha256': digest(OUT / 'consumer-matrix.json'), 'report_sha256': digest(OUT / 'critical-review.md')}, indent=2))
