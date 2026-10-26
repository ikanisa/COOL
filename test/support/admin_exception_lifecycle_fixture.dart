// Authored parser and widget protocol doubles. These records are synthetic.
Map<String, dynamic> exceptionLifecycleFixture(String name) {
  const exception = '73300000-0000-4000-8000-000000000001';
  const actor = '73300000-0000-4000-8000-000000000002';
  const checked = '2026-10-01T11:25:32.000000Z';
  String instant(int second) => DateTime.utc(
    2026,
    10,
    1,
    11,
    25,
    second,
  ).toIso8601String().replaceFirst('.000Z', '.000000Z');
  String id(int value) =>
      '73310000-0000-4000-8000-${value.toString().padLeft(12, '0')}';
  final escalations = List.generate(
    4,
    (index) => <String, dynamic>{
      'id': id(4 - index),
      'state': index == 0 ? 'obsolete' : 'delivered',
      'read_at': index == 3 ? instant(25) : null,
      'queued_at': instant(30 - index * 2),
      'delivered_at': index == 0 ? null : instant(31 - index * 2),
      'recipient_id': actor,
      'source_revision': 7 - index * 2,
    },
  );
  if (name == 'inbox') {
    return {
      'contract_version': 1,
      'channel': 'admin_inbox',
      'checked_at': checked,
      'sample_valid_until': '2026-10-01T11:26:32.000000Z',
      'rows': [
        for (var index = 1; index < 4; index++)
          {
            'escalation_id': escalations[index]['id'],
            'exception_id': exception,
            'source_revision': escalations[index]['source_revision'],
            'reason_code': index == 1
                ? 'deadline_exceeded'
                : 'operator_escalation',
            'source_active': false,
            'current_source_revision': 8,
            'delivered_at': escalations[index]['delivered_at'],
            'read_at': escalations[index]['read_at'],
          },
      ],
    };
  }
  final unassigned = name == 'unassigned' || name == 'unassigned-resolved';
  if (name != 'workflow' && !unassigned) throw ArgumentError.value(name);
  final cleared = name == 'unassigned-resolved' || !unassigned;
  return {
    'contract_version': 1,
    'exception_id': exception,
    'source_revision': name == 'unassigned-resolved'
        ? 2
        : unassigned
        ? 1
        : 8,
    'workflow_revision': name == 'unassigned-resolved'
        ? 1
        : unassigned
        ? 0
        : 8,
    'source_active': !cleared,
    'status': name == 'unassigned-resolved'
        ? 'resolved'
        : unassigned
        ? 'unassigned'
        : 'source_cleared',
    'assignee_id': unassigned ? null : actor,
    'due_at': unassigned ? null : instant(29),
    'overdue': false,
    'recipient_available': !unassigned,
    'checked_at': checked,
    'sample_valid_until': '2026-10-01T11:26:32.000000Z',
    'escalations': unassigned ? <Map<String, dynamic>>[] : escalations,
  };
}
