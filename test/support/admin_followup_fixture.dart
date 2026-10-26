import 'package:collect_app/admin/core/admin_exception_followup_v2_models.dart';
import 'package:collect_app/admin/core/admin_exception_workflow_models.dart';

// Authored protocol doubles for parser/client/widget tests. These values are
// synthetic and establish no SQL, hosted, provider or release result.
Map<String, dynamic> followupFixture(
  String name, {
  String exceptionId = '71100000-0000-4000-8000-000000000001',
  String actorId = '71100000-0000-4000-8000-000000000002',
}) {
  const checked = '2026-10-01T12:30:10.000000Z';
  const expires = '2026-10-01T12:31:40.000000Z';
  final binding = <String, dynamic>{
    'request_id': '71100000-0000-4000-8000-000000000003',
    'exception_id': exceptionId,
    'source_revision': 1,
    'workflow_revision': 0,
    'action': 'assign',
    'assignee_id': actorId,
    'due_at': '2026-10-02T12:30:10.000000Z',
    'reason_code': 'review_started',
    'expires_at': expires,
  };
  if (name == 'assignment-binding') return binding;
  final intent = AdminExceptionWorkflowIntent.parse({
    'p_request_id': binding['request_id'],
    'p_exception_id': exceptionId,
    'p_expected_source_revision': 1,
    'p_expected_workflow_revision': 0,
    'p_action': 'assign',
    'p_assignee_id': actorId,
    'p_due_at': binding['due_at'],
    'p_reason_code': 'review_started',
    'p_expires_at': expires,
  });
  final fingerprint = adminExceptionFollowupFingerprint(intent);
  final receipt = <String, dynamic>{
    'contract_version': 2,
    'request_id': binding['request_id'],
    'exception_id': exceptionId,
    'source_revision': 1,
    'workflow_revision': 1,
    'action': 'assign',
    'escalation_id': null,
    'source_resolved': false,
    'financial_action': false,
    'send_action': false,
    'recorded_at': checked,
    'request_fingerprint': fingerprint,
  };
  if (name == 'assignment-receipt') return receipt;
  if (name == 'recorded-lookup') {
    return {
      'contract_version': 2,
      'request_id': binding['request_id'],
      'request_fingerprint': fingerprint,
      'expires_at': expires,
      'checked_at': checked,
      'sample_valid_until': '2026-10-01T12:31:10.000000Z',
      'status': 'recorded',
      'receipt': receipt,
    };
  }
  if (name == 'directory-first' || name == 'directory-last') {
    final rows = List.generate(
      31,
      (index) => <String, dynamic>{
        'operator_id': index == 0
            ? actorId
            : '71110000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
        'display_label': 'Collect ID ${500001 + index}',
        'created_at': DateTime.utc(2026, 10, 1, 11)
            .subtract(Duration(minutes: index))
            .toIso8601String()
            .replaceFirst('.000Z', '.000000Z'),
      },
    );
    final first = name == 'directory-first';
    return {
      'contract_version': 2,
      'scope': 'platform_global',
      'checked_at': checked,
      'sample_valid_until': '2026-10-01T12:31:10.000000Z',
      'limit': 25,
      'rows': first ? rows.take(25).toList() : rows.skip(25).toList(),
      'next_cursor': first
          ? {
              'created_at': rows[24]['created_at'],
              'operator_id': rows[24]['operator_id'],
            }
          : null,
    };
  }
  throw ArgumentError.value(name, 'name', 'Unknown synthetic protocol case');
}
