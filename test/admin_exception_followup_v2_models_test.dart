import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_exception_checkpoint.dart';
import 'package:collect_app/admin/core/admin_exception_followup_v2_models.dart';
import 'package:collect_app/admin/core/admin_exception_workflow_models.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

// Declared contract doubles. Exact accepted190000 SQL observations are also
// tested below; these synthetic rows are not additional SQL observations.
const _request = '99490000-0000-4000-8000-000000000010';
const _exception = '99490000-0000-4000-8000-000000000020';
const _assignee = '99490000-0000-4000-8000-000000000030';
const _actor = '99490000-0000-4000-8000-000000000040';
const _other = '99490000-0000-4000-8000-000000000050';
const _expires = '2026-10-01T12:31:30.000000Z';
const _due = '2026-10-02T12:30:00.000001Z';
const _at = '2026-10-01T12:30:10.000000Z';
const _hashes = {
  'assign': 'a05f09b652c5da09f65d099d2159ea5b081a31456a8f415b44d6da411eb78932',
  'escalate':
      'cebd646da9d34684e5779d64d2d0b8dece7e8bf89ee915ff60d206f74e2d4573',
  'resolve': 'b1854607da92d1d26609c7a09e7a24093f8cffe6446966f0873f130a9b336181',
};
String _owner([String actor = _actor]) =>
    adminExceptionOwnerDigest('workflow:$actor:$_exception');
Map<String, dynamic> _copy(Map<String, dynamic> row) =>
    jsonDecode(jsonEncode(row)) as Map<String, dynamic>;
String _wire(DateTime at) => at.toUtc().toIso8601String().replaceFirstMapped(
  RegExp(r'\.(\d{3})Z$'),
  (match) => '.${match[1]}000Z',
);

AdminExceptionWorkflowIntent _intent(
  String action, [
  Map<String, dynamic> patch = const {},
]) => AdminExceptionWorkflowIntent.parse({
  'p_request_id': _request,
  'p_exception_id': _exception,
  'p_expected_source_revision': 4,
  'p_expected_workflow_revision': 2,
  'p_action': action,
  'p_assignee_id': action == 'assign' ? _assignee : null,
  'p_due_at': action == 'assign' ? _due : null,
  'p_reason_code': action == 'assign'
      ? 'review_started'
      : action == 'escalate'
      ? 'owner_review_required'
      : 'source_rechecked',
  'p_expires_at': _expires,
  ...patch,
});
AdminExceptionFollowupReference _reference(String action) =>
    AdminExceptionFollowupReference.fromIntent(_intent(action));
Map<String, dynamic> _receipt(String action) => {
  'contract_version': 2,
  'request_id': _request,
  'exception_id': _exception,
  'source_revision': 4,
  'workflow_revision': 3,
  'action': action,
  'escalation_id': action == 'escalate' ? _other : null,
  'source_resolved': action == 'resolve',
  'financial_action': false,
  'send_action': false,
  'recorded_at': _at,
  'request_fingerprint': _hashes[action],
};
Map<String, dynamic> _lookup(
  String action, {
  String status = 'recorded',
  DateTime? checkedAt,
}) {
  final checked = checkedAt ?? DateTime.parse(_at);
  return {
    'contract_version': 2,
    'request_id': _request,
    'request_fingerprint': _hashes[action],
    'expires_at': _expires,
    'checked_at': _wire(checked),
    'sample_valid_until': _wire(checked.add(const Duration(seconds: 60))),
    'status': status,
    'receipt': status == 'recorded' ? _receipt(action) : null,
  };
}

Map<String, dynamic> _operator(String id, String label, String created) => {
  'operator_id': id,
  'display_label': label,
  'created_at': created,
};
Map<String, dynamic> _directory() => {
  'contract_version': 2,
  'scope': 'platform_global',
  'checked_at': _at,
  'sample_valid_until': '2026-10-01T12:31:10.000000Z',
  'limit': 2,
  'rows': [
    _operator(_other, 'Collect ID 500001', '2026-10-01T12:00:00.000000Z'),
    _operator(_actor, 'Collect ID 500002', '2026-10-01T12:00:00.000000Z'),
  ],
  'next_cursor': {
    'created_at': '2026-10-01T12:00:00.000000Z',
    'operator_id': _actor,
  },
};
const _query = AdminExceptionFollowupDirectoryQuery(limit: 2);

Map<String, dynamic> _sql(String name) => Map<String, dynamic>.from(
  jsonDecode(
        File(
          'scripts/tests/fixtures/exception_followup_v2/observed-$name.json',
        ).readAsStringSync(),
      )
      as Map,
);
AdminExceptionWorkflowIntent _sqlIntent() {
  final binding = _sql('assignment-binding');
  return AdminExceptionWorkflowIntent.parse({
    'p_request_id': binding['request_id'],
    'p_exception_id': binding['exception_id'],
    'p_expected_source_revision': binding['source_revision'],
    'p_expected_workflow_revision': binding['workflow_revision'],
    'p_action': binding['action'],
    'p_assignee_id': binding['assignee_id'],
    'p_due_at': binding['due_at'],
    'p_reason_code': binding['reason_code'],
    'p_expires_at': binding['expires_at'],
  });
}

AdminExceptionFollowupReference _sqlLookupReference(Map<String, dynamic> raw) =>
    AdminExceptionFollowupReference.parse({
      'p_request_id': raw['request_id'],
      'p_exception_id': _sqlIntent().exceptionId,
      'p_expected_source_revision': 1,
      'p_expected_workflow_revision': 0,
      'p_action': 'assign',
      'p_expires_at': raw['expires_at'],
      'request_fingerprint': raw['request_fingerprint'],
    });

void main() {
  test(
    'malformed v3 private metadata quarantines only exact v2 original binding',
    () {
      final bookmark = AdminExceptionFollowupBookmark.fromIntent(
        _intent('assign'),
        _owner(),
        _actor,
      );
      final rejected = jsonDecode(bookmark.encode()) as Map<String, dynamic>;
      rejected['private'] = 'PRIVATE_CANARY';
      (rejected['request'] as Map)['p_assignee_id'] = _assignee;
      (rejected['request'] as Map)['p_due_at'] = _due;
      (rejected['request'] as Map)['p_reason_code'] = 'PRIVATE_CANARY';
      final quarantined = AdminExceptionFollowupQuarantine.scrub(
        jsonEncode(rejected),
        _owner(),
        _actor,
        _exception,
      );
      expect(quarantined.reference!.toJson(), bookmark.reference.toJson());
      expect(quarantined.requestId, _request);
      final encoded = quarantined.encode();
      expect(jsonDecode(encoded)['version'], 4);
      for (final private in [
        'PRIVATE_CANARY',
        'p_assignee_id',
        'p_due_at',
        'p_reason_code',
        _actor,
        _assignee,
      ]) {
        expect(encoded, isNot(contains(private)));
      }
      final restored = AdminExceptionFollowupQuarantine.parse(
        encoded,
        _owner(),
        _actor,
        _exception,
      );
      expect(
        restored.reference!.lookupParameters,
        bookmark.reference.lookupParameters,
      );
      expect(
        AdminExceptionFollowupLookup.parse(
          _lookup('assign'),
          restored.reference!,
        ).status,
        'recorded',
      );
      // A parsed negative read remains a negative observation, never a quarantine
      // clearance rule. Only the UI's matching v2 recorded proof can clear it.
      expect(
        AdminExceptionFollowupLookup.parse(
          _lookup('assign', status: 'not_recorded'),
          restored.reference!,
        ).receipt,
        isNull,
      );
    },
  );
  for (final fingerprint in [null, 'PRIVATE_BAD_HASH', 'A' * 64]) {
    test(
      'missing or bad v3 fingerprint $fingerprint remains opaque-only quarantine after reload',
      () {
        final raw =
            jsonDecode(
                  AdminExceptionFollowupBookmark.fromIntent(
                    _intent('assign'),
                    _owner(),
                    _actor,
                  ).encode(),
                )
                as Map<String, dynamic>;
        final request = raw['request'] as Map;
        if (fingerprint == null) {
          request.remove('request_fingerprint');
        } else {
          request['request_fingerprint'] = fingerprint;
        }
        raw['private'] = 'PRIVATE_CANARY';
        final quarantined = AdminExceptionFollowupQuarantine.scrub(
          jsonEncode(raw),
          _owner(),
          _actor,
          _exception,
        );
        expect(quarantined.reference, isNull);
        expect(quarantined.requestId, _request);
        final restored = AdminExceptionFollowupQuarantine.parse(
          quarantined.encode(),
          _owner(),
          _actor,
          _exception,
        );
        expect(restored.reference, isNull);
        expect(restored.requestId, _request);
        expect(restored.encode(), isNot(contains('PRIVATE')));
        expect(restored.encode(), isNot(contains('request_fingerprint')));
      },
    );
  }
  test(
    'foreign owner exception invalid original and excessive bytes never produce quarantine lookup',
    () {
      final raw =
          jsonDecode(
                AdminExceptionFollowupBookmark.fromIntent(
                  _intent('assign'),
                  _owner(),
                  _actor,
                ).encode(),
              )
              as Map<String, dynamic>;
      for (final rejected in [
        jsonEncode({...raw, 'owner_digest': _owner(_other)}),
        jsonEncode({...raw, 'version': 2}),
        jsonEncode({...raw, 'version': '3'}),
        jsonEncode({...raw, 'version': 99}),
        jsonEncode({
          ...raw,
          'request': {...raw['request'] as Map, 'p_exception_id': _other},
        }),
        jsonEncode({
          ...raw,
          'request': {...raw['request'] as Map, 'p_request_id': 'PRIVATE_UUID'},
        }),
        'PRIVATE_CANARY',
        'x' * 16385,
      ]) {
        final quarantined = AdminExceptionFollowupQuarantine.scrub(
          rejected,
          _owner(),
          _actor,
          _exception,
        );
        expect(quarantined.reference, isNull);
        expect(quarantined.requestId, isNull);
        expect(quarantined.encode(), isNot(contains('PRIVATE')));
      }
      expect(
        () => AdminExceptionFollowupQuarantine.scrub(
          jsonEncode(raw),
          _owner(),
          _other,
          _exception,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'quarantine closed canonical parse rejects private cross-owner cross-original fields',
    () {
      final quarantined = AdminExceptionFollowupQuarantine.scrub(
        AdminExceptionFollowupBookmark.fromIntent(
          _intent('assign'),
          _owner(),
          _actor,
        ).encode(),
        _owner(),
        _actor,
        _exception,
      );
      final raw = jsonDecode(quarantined.encode()) as Map<String, dynamic>;
      for (final patch in [
        {'version': 3},
        {'version': 4.0},
        {'owner_digest': _owner(_other)},
        {'exception_id': _other},
        {'original_request_id': _other},
        {'authorization': 'PRIVATE_CANARY'},
        {
          'original_reference': {
            ...raw['original_reference'] as Map,
            'p_exception_id': _other,
          },
        },
        {
          'original_reference': {
            ...raw['original_reference'] as Map,
            'request_fingerprint': 'PRIVATE',
          },
        },
      ]) {
        expect(
          () => AdminExceptionFollowupQuarantine.parse(
            jsonEncode({...raw, ...patch}),
            _owner(),
            _actor,
            _exception,
          ),
          throwsFormatException,
        );
      }
      expect(
        () => AdminExceptionFollowupQuarantine.parse(
          ' ${quarantined.encode()}',
          _owner(),
          _actor,
          _exception,
        ),
        throwsFormatException,
      );
      expect(
        () => AdminExceptionFollowupQuarantine.parse(
          quarantined.encode().replaceFirst(
            '"version":4',
            '"version":4,"version":4',
          ),
          _owner(),
          _actor,
          _exception,
        ),
        throwsFormatException,
      );
      for (final key in raw.keys) {
        expect(
          () => AdminExceptionFollowupQuarantine.parse(
            jsonEncode({...raw}..remove(key)),
            _owner(),
            _actor,
            _exception,
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'actual SQL assignment ACK matches independently canonical Dart fingerprint',
    () {
      final intent = _sqlIntent(),
          reference = AdminExceptionFollowupReference.fromIntent(intent);
      final receipt = AdminExceptionFollowupReceipt.parse(
        _sql('assignment-receipt'),
        reference,
      );
      expect(
        receipt.requestFingerprint,
        '7db63c63d34cda696adccd50a6474dfcca69b678e4f347b80963312324123000',
      );
      expect(receipt.revision, 1);
      expect(
        receipt.recordedAt,
        DateTime.parse(_sql('assignment-receipt')['recorded_at'] as String),
      );
    },
  );
  for (final name in ['recorded-lookup', 'after-commit-lookup']) {
    test('actual SQL $name retains immutable original ACK', () {
      final raw = _sql(name);
      final ack = raw['receipt'] as Map;
      // The after-commit observation is a distinct original action with
      // expected workflow predecessor2, not the earlier assignment UUID.
      final original = name == 'recorded-lookup'
          ? AdminExceptionFollowupReference.fromIntent(_sqlIntent())
          : AdminExceptionFollowupReference.parse({
              'p_request_id': raw['request_id'],
              'p_exception_id': ack['exception_id'],
              'p_expected_source_revision': ack['source_revision'],
              'p_expected_workflow_revision': 2,
              'p_action': ack['action'],
              'p_expires_at': raw['expires_at'],
              'request_fingerprint': raw['request_fingerprint'],
            });
      final lookup = AdminExceptionFollowupLookup.parse(raw, original);
      expect(lookup.status, 'recorded');
      expect(
        lookup.receipt!.recordedAt,
        DateTime.parse(ack['recorded_at'] as String),
      );
      expect(lookup.receipt!.requestId, raw['request_id']);
      expect(lookup.receipt!.requestFingerprint, ack['request_fingerprint']);
      expect(lookup.receipt!.revision, ack['workflow_revision']);
      expect(lookup.provesExpiredAbsence(lookup.checkedAt), isFalse);
      if (name == 'after-commit-lookup') {
        expect(
          () => AdminExceptionFollowupLookup.parse(
            raw,
            AdminExceptionFollowupReference.fromIntent(_sqlIntent()),
          ),
          throwsFormatException,
          reason:
              'The earlier original must remain a strict cross-request refusal.',
        );
      }
    });
  }
  for (final name in [
    'in-progress-lookup',
    'foreign-lookup',
    'expired-unrecorded-lookup',
  ]) {
    test('actual SQL $name proves only its original scoped observation', () {
      final raw = _sql(name), reference = _sqlLookupReference(raw);
      final lookup = AdminExceptionFollowupLookup.parse(raw, reference);
      expect(lookup.receipt, isNull);
      expect(
        lookup.provesExpiredAbsence(lookup.checkedAt),
        name == 'expired-unrecorded-lookup',
      );
      expect(lookup.provesExpiredAbsence(lookup.validUntil), isFalse);
    });
  }
  test(
    'actual SQL directory pages retain paired keyset and minimal labels',
    () {
      final first = AdminExceptionFollowupDirectory.parse(
        _sql('directory-first'),
        query: const AdminExceptionFollowupDirectoryQuery(),
      );
      final last = AdminExceptionFollowupDirectory.parse(
        _sql('directory-last'),
        query: AdminExceptionFollowupDirectoryQuery(before: first.nextCursor),
      );
      expect(first.rows, hasLength(25));
      expect(last.rows, hasLength(6));
      expect(last.nextCursor, isNull);
      expect({
        ...first.rows.map((row) => row.operatorId),
        ...last.rows.map((row) => row.operatorId),
      }, hasLength(31));
      expect(first.rows.first.displayLabel, 'Collect ID 695494');
      expect(last.rows.last.displayLabel, 'Collect ID 741070');
    },
  );
  test(
    'v2 expected workflow revision stops before terminal recorded revision',
    () {
      final allowed = _intent('assign', {
        'p_expected_workflow_revision': 999999999,
      });
      expect(
        AdminExceptionFollowupReference.fromIntent(allowed).workflowRevision,
        999999999,
      );
      final receipt = {
        ..._receipt('assign'),
        'workflow_revision': 1000000000,
        'request_fingerprint': adminExceptionFollowupFingerprint(allowed),
      };
      expect(
        AdminExceptionFollowupReceipt.parse(
          receipt,
          AdminExceptionFollowupReference.fromIntent(allowed),
        ).revision,
        1000000000,
      );
      final invalid = _intent('assign', {
        'p_expected_workflow_revision': 1000000000,
      });
      expect(
        () => AdminExceptionFollowupReference.fromIntent(invalid),
        throwsFormatException,
      );
      expect(
        () => adminExceptionFollowupFingerprint(invalid),
        throwsFormatException,
      );
      final raw = _reference('assign').toJson();
      expect(
        () => AdminExceptionFollowupReference.parse({
          ...raw,
          'p_expected_workflow_revision': 1000000000,
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'full v2 intent rejects finite timestamp domains outside years1 through9999',
    () {
      for (final invalid in [DateTime.utc(0), DateTime.utc(10000)]) {
        final original = _intent('assign');
        final expiry = AdminExceptionWorkflowIntent(
          requestId: original.requestId,
          exceptionId: original.exceptionId,
          sourceRevision: original.sourceRevision,
          workflowRevision: original.workflowRevision,
          action: 'assign',
          assigneeId: original.assigneeId,
          dueAt: original.dueAt,
          expiresAt: invalid,
        );
        final due = AdminExceptionWorkflowIntent(
          requestId: original.requestId,
          exceptionId: original.exceptionId,
          sourceRevision: original.sourceRevision,
          workflowRevision: original.workflowRevision,
          action: 'assign',
          assigneeId: original.assigneeId,
          dueAt: invalid,
          expiresAt: original.expiresAt,
        );
        expect(
          () => AdminExceptionFollowupReference.fromIntent(expiry),
          throwsFormatException,
        );
        expect(
          () => AdminExceptionFollowupReference.fromIntent(due),
          throwsFormatException,
        );
      }
    },
  );
  for (final action in ['assign', 'escalate', 'resolve']) {
    test('$action fingerprint matches independent ten-line golden bytes', () {
      final intent = _intent(action),
          text =
              'collect-exception-workflow-v2\n'
              '$_request\n$_exception\n4\n2\n$action\n'
              '${action == 'assign' ? _assignee : '-'}\n'
              '${action == 'assign' ? _due : '-'}\n'
              '${action == 'assign'
                  ? 'review_started'
                  : action == 'escalate'
                  ? 'owner_review_required'
                  : 'source_rechecked'}\n'
              '$_expires';
      expect(text.split('\n'), hasLength(10));
      expect(adminExceptionFollowupFingerprint(intent), _hashes[action]);
      expect(sha256.convert(utf8.encode(text)).toString(), _hashes[action]);
      expect(
        sha256.convert(utf8.encode('$text\n')).toString(),
        isNot(_hashes[action]),
      );
      expect(
        sha256.convert(utf8.encode('\n$text')).toString(),
        isNot(_hashes[action]),
      );
    });
    test(
      '$action bookmark restores original-only metadata without action inputs',
      () {
        final intent = _intent(action),
            bookmark = AdminExceptionFollowupBookmark.fromIntent(
              intent,
              _owner(),
              _actor,
            ),
            encoded = bookmark.encode(),
            restored = AdminExceptionFollowupBookmark.decode(
              encoded,
              _owner(),
              _actor,
              _exception,
            ),
            request = jsonDecode(encoded)['request'] as Map;
        expect(restored.reference.toJson(), bookmark.reference.toJson());
        expect(restored.reference.requestFingerprint, _hashes[action]);
        expect(request.keys.toSet(), {
          'p_request_id',
          'p_exception_id',
          'p_expected_source_revision',
          'p_expected_workflow_revision',
          'p_action',
          'p_expires_at',
          'request_fingerprint',
        });
        expect(encoded, isNot(contains(_actor)));
        expect(encoded, isNot(contains(_assignee)));
        expect(encoded, isNot(contains('p_assignee_id')));
        expect(encoded, isNot(contains('p_due_at')));
        expect(encoded, isNot(contains('p_reason_code')));
        expect(restored.reference.lookupParameters, {
          'p_request_id': _request,
          'p_request_fingerprint': _hashes[action],
          'p_expires_at': _expires,
        });
        expect(
          () => restored.reference.toJson()['p_action'] = 'send',
          throwsUnsupportedError,
        );
        expect(
          () => restored.reference.lookupParameters['p_action'] = action,
          throwsUnsupportedError,
        );
      },
    );
    test('$action v2 original ACK delegates immutable workflow invariants', () {
      final reference = _reference(action),
          bookmark = AdminExceptionFollowupBookmark.fromIntent(
            _intent(action),
            _owner(),
            _actor,
          ),
          receipt = bookmark.receipt(_receipt(action));
      expect(receipt.receipt, isA<AdminExceptionWorkflowReceipt>());
      expect(receipt.requestId, reference.requestId);
      expect(receipt.exceptionId, reference.exceptionId);
      expect(receipt.sourceRevision, reference.sourceRevision);
      expect(receipt.revision, reference.workflowRevision + 1);
      expect(receipt.action, action);
      expect(receipt.requestFingerprint, reference.requestFingerprint);
      expect(receipt.escalationId, action == 'escalate' ? _other : null);
    });
    test(
      '$action lookup binds historical ACK without inferring current state',
      () {
        final bookmark = AdminExceptionFollowupBookmark.fromIntent(
              _intent(action),
              _owner(),
              _actor,
            ),
            lookup = bookmark.lookup(_lookup(action));
        expect(lookup.status, 'recorded');
        expect(lookup.receipt!.action, action);
        expect(lookup.requestId, _request);
        expect(lookup.requestFingerprint, _hashes[action]);
        expect(lookup.expiresAt, DateTime.parse(_expires));
        expect(lookup.isFresh(DateTime.parse(_at)), isTrue);
        expect(lookup.provesExpiredAbsence(DateTime.parse(_expires)), isFalse);
      },
    );
  }
  test(
    'assignment to another operator changes fingerprint without persisting identity',
    () {
      final original = _intent('assign'),
          changed = _intent('assign', {'p_assignee_id': _other});
      expect(
        adminExceptionFollowupFingerprint(original),
        isNot(adminExceptionFollowupFingerprint(changed)),
      );
      final bookmark = AdminExceptionFollowupBookmark.fromIntent(
        changed,
        _owner(),
        _actor,
      );
      expect(bookmark.encode(), isNot(contains(_other)));
      expect(bookmark.encode(), isNot(contains(_assignee)));
      expect(
        () => original.encode(_owner(), _actor),
        throwsFormatException,
        reason: 'The legacy self-only recovery guard must stay strict.',
      );
    },
  );
  test('every original request component binds its fingerprint', () {
    for (final patch in [
      {'p_request_id': _other},
      {'p_exception_id': _other},
      {'p_expected_source_revision': 5},
      {'p_expected_workflow_revision': 3},
      {'p_assignee_id': _other},
      {'p_due_at': '2026-10-02T12:30:00.000002Z'},
      {'p_expires_at': '2026-10-01T12:31:30.000001Z'},
    ]) {
      expect(
        adminExceptionFollowupFingerprint(_intent('assign', patch)),
        isNot(_hashes['assign']),
      );
    }
    expect(_hashes.values.toSet(), hasLength(3));
  });
  test('fingerprints normalize input instants to exact UTC microseconds', () {
    final original = _intent('assign'),
        local = AdminExceptionWorkflowIntent(
          requestId: original.requestId,
          exceptionId: original.exceptionId,
          sourceRevision: original.sourceRevision,
          workflowRevision: original.workflowRevision,
          action: original.action,
          assigneeId: original.assigneeId,
          dueAt: DateTime.parse('2026-10-02T14:30:00.000001+02:00'),
          expiresAt: DateTime.parse('2026-10-01T14:31:30+02:00'),
        );
    expect(adminExceptionFollowupFingerprint(local), _hashes['assign']);
    expect(
      AdminExceptionFollowupReference.fromIntent(local).lookupParameters,
      _reference('assign').lookupParameters,
    );
  });
  test('invalid or partial live assignment cannot create a valid bookmark', () {
    for (final intent in [
      AdminExceptionWorkflowIntent(
        requestId: _request,
        exceptionId: _exception,
        sourceRevision: 4,
        workflowRevision: 2,
        action: 'assign',
        expiresAt: DateTime.parse(_expires),
      ),
      AdminExceptionWorkflowIntent(
        requestId: _request,
        exceptionId: _exception,
        sourceRevision: 4,
        workflowRevision: 2,
        action: 'send',
        expiresAt: DateTime.parse(_expires),
      ),
    ]) {
      expect(
        () =>
            AdminExceptionFollowupBookmark.fromIntent(intent, _owner(), _actor),
        throwsFormatException,
      );
    }
  });
  test('bookmarks reject another owner purpose actor or exception', () {
    final bookmark = AdminExceptionFollowupBookmark.fromIntent(
      _intent('assign'),
      _owner(),
      _actor,
    );
    for (final tuple in [
      (_owner(_other), _other, _exception),
      (_owner(), _other, _exception),
      (_owner(), _actor, _other),
      (adminExceptionOwnerDigest(_actor), _actor, _exception),
    ]) {
      expect(
        () => AdminExceptionFollowupBookmark.decode(
          bookmark.encode(),
          tuple.$1,
          tuple.$2,
          tuple.$3,
        ),
        throwsFormatException,
      );
    }
  });
  test(
    'canonical bookmark JSON rejects duplicates private fields and legacy intents',
    () {
      final bookmark = AdminExceptionFollowupBookmark.fromIntent(
            _intent('assign'),
            _owner(),
            _actor,
          ),
          encoded = bookmark.encode();
      for (final altered in [
        ' $encoded',
        encoded.replaceFirst('{', '{"version":3,'),
        encoded.replaceFirst('{', r'{"\u0076ersion":3,'),
        encoded.replaceFirst('{', '{"actor_id":"$_actor",'),
        encoded.replaceFirst(
          '"request":{',
          '"request":{"p_assignee_id":"$_assignee",',
        ),
        encoded.replaceFirst(
          '"request":{',
          '"request":{"private_payload":"PRIVATE_CANARY",',
        ),
        encoded.replaceFirst('"version":3', '"version":2'),
        encoded.replaceFirst('"version":3', '"version":3.0'),
        '${' ' * 2048}$encoded',
      ]) {
        expect(
          () => AdminExceptionFollowupBookmark.decode(
            altered,
            _owner(),
            _actor,
            _exception,
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'reference refuses malformed revisions fields actions fingerprints and times',
    () {
      final reference = _reference('assign').toJson();
      for (final patch in [
        {'p_request_id': _request.replaceFirst('9949', 'ABCD')},
        {'p_exception_id': 'PRIVATE_CANARY'},
        {'p_expected_source_revision': 0},
        {'p_expected_source_revision': 4.0},
        {'p_expected_workflow_revision': -1},
        {'p_expected_workflow_revision': 2.0},
        {'p_action': 'notify'},
        {'p_expires_at': '2026-02-30T12:31:30.000000Z'},
        {'request_fingerprint': 'A' * 64},
        {'request_fingerprint': 'a' * 63},
        {'p_assignee_id': _assignee},
      ]) {
        expect(
          () => AdminExceptionFollowupReference.parse({...reference, ...patch}),
          throwsFormatException,
        );
      }
      for (final key in reference.keys) {
        expect(
          () => AdminExceptionFollowupReference.parse(
            {...reference}..remove(key),
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'ACK rejects cross-original revision action escalation and financial claims',
    () {
      final raw = _receipt('assign'), reference = _reference('assign');
      for (final patch in [
        {'contract_version': 1},
        {'contract_version': 2.0},
        {'request_id': _other},
        {'exception_id': _other},
        {'source_revision': 5},
        {'workflow_revision': 4},
        {'source_revision': 4.0},
        {'workflow_revision': 3.0},
        {'action': 'escalate'},
        {'escalation_id': _other},
        {'source_resolved': true},
        {'financial_action': true},
        {'send_action': true},
        {'financial_action': 0},
        {'recorded_at': _expires},
        {'request_fingerprint': 'a' * 64},
        {'assignee_id': _assignee},
        {'destination': 'PRIVATE_CANARY'},
      ]) {
        expect(
          () => AdminExceptionFollowupReceipt.parse({
            ...raw,
            ...patch,
          }, reference),
          throwsFormatException,
        );
      }
      for (final key in raw.keys) {
        expect(
          () => AdminExceptionFollowupReceipt.parse(
            {...raw}..remove(key),
            reference,
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'original ACK can be verified by a different authorized operator reference',
    () {
      final original = AdminExceptionFollowupBookmark.fromIntent(
            _intent('assign'),
            _owner(),
            _actor,
          ),
          anotherOwner = AdminExceptionFollowupBookmark.fromIntent(
            _intent('assign'),
            _owner(_other),
            _other,
          );
      expect(original.ownerDigest, isNot(anotherOwner.ownerDigest));
      expect(
        original.reference.requestFingerprint,
        anotherOwner.reference.requestFingerprint,
      );
      expect(anotherOwner.receipt(_receipt('assign')).requestId, _request);
      expect(
        () => AdminExceptionFollowupBookmark.decode(
          original.encode(),
          _owner(_other),
          _other,
          _exception,
        ),
        throwsFormatException,
      );
    },
  );
  for (final status in ['not_recorded', 'in_progress']) {
    test(
      '$status lookup retains the complete original binding with no receipt',
      () {
        final lookup = AdminExceptionFollowupLookup.parse(
          _lookup('assign', status: status),
          _reference('assign'),
        );
        expect(lookup.status, status);
        expect(lookup.receipt, isNull);
        expect(lookup.requestFingerprint, _hashes['assign']);
        expect(lookup.provesExpiredAbsence(DateTime.parse(_at)), isFalse);
      },
    );
  }
  test(
    'lookup rejects cross-original fingerprint expiry private data and future ACK',
    () {
      final raw = _lookup('assign'), reference = _reference('assign');
      for (final patch in [
        {'contract_version': 1},
        {'contract_version': 2.0},
        {'request_id': _other},
        {'request_fingerprint': 'a' * 64},
        {'expires_at': '2026-10-01T12:31:30.000001Z'},
        {'status': 'delivered'},
        {'status': 'not_recorded'},
        {'receipt': null},
        {'sample_valid_until': _at},
        {'authorization': 'PRIVATE_CANARY'},
        {
          'receipt': {
            ..._receipt('assign'),
            'recorded_at': '2026-10-01T12:30:10.000001Z',
          },
        },
        {
          'receipt': {..._receipt('assign'), 'request_fingerprint': 'a' * 64},
        },
      ]) {
        expect(
          () =>
              AdminExceptionFollowupLookup.parse({...raw, ...patch}, reference),
          throwsFormatException,
        );
      }
      for (final key in raw.keys) {
        expect(
          () => AdminExceptionFollowupLookup.parse(
            {...raw}..remove(key),
            reference,
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'fresh absence after original expiry alone allows clearing without replay',
    () {
      final expiry = DateTime.parse(_expires), reference = _reference('assign');
      final before = AdminExceptionFollowupLookup.parse(
        _lookup(
          'assign',
          status: 'not_recorded',
          checkedAt: expiry.subtract(const Duration(microseconds: 1)),
        ),
        reference,
      );
      expect(before.provesExpiredAbsence(expiry), isFalse);
      final after = AdminExceptionFollowupLookup.parse(
        _lookup('assign', status: 'not_recorded', checkedAt: expiry),
        reference,
      );
      expect(
        after.provesExpiredAbsence(
          expiry.subtract(const Duration(microseconds: 1)),
        ),
        isFalse,
      );
      expect(after.provesExpiredAbsence(expiry), isTrue);
      expect(after.provesExpiredAbsence(after.validUntil), isFalse);
      final busy = AdminExceptionFollowupLookup.parse(
        _lookup('assign', status: 'in_progress', checkedAt: expiry),
        reference,
      );
      expect(busy.provesExpiredAbsence(expiry), isFalse);
      final recorded = AdminExceptionFollowupLookup.parse(
        _lookup('assign', checkedAt: expiry),
        reference,
      );
      expect(recorded.provesExpiredAbsence(expiry), isFalse);
    },
  );
  test(
    'directory has bounded private labels immutable rows and fresh eligibility',
    () {
      final directory = AdminExceptionFollowupDirectory.parse(
        _directory(),
        query: _query,
      );
      expect(directory.scope, 'platform_global');
      expect(directory.limit, 2);
      expect(directory.rows.map((row) => row.displayLabel), [
        'Collect ID 500001',
        'Collect ID 500002',
      ]);
      expect(directory.isEligible(_other, DateTime.parse(_at)), isTrue);
      expect(directory.isEligible(_assignee, DateTime.parse(_at)), isFalse);
      expect(directory.isEligible(_other, directory.validUntil), isFalse);
      expect(
        directory.isFresh(
          directory.checkedAt.subtract(const Duration(seconds: 5)),
        ),
        isTrue,
      );
      expect(
        directory.isFresh(
          directory.checkedAt.subtract(
            const Duration(seconds: 5, microseconds: 1),
          ),
        ),
        isFalse,
      );
      expect(() => directory.rows.clear(), throwsUnsupportedError);
    },
  );
  test(
    'directory query keeps paired original cursor exact parameters and stable equality',
    () {
      final cursor = AdminExceptionFollowupCursor.parse(
            _directory()['next_cursor'],
          ),
          query = AdminExceptionFollowupDirectoryQuery(
            limit: 2,
            before: cursor,
          );
      expect(query.parameters, {
        'p_limit': 2,
        'p_before_created_at': '2026-10-01T12:00:00.000000Z',
        'p_before_operator_id': _actor,
      });
      expect(
        query,
        AdminExceptionFollowupDirectoryQuery(
          limit: 2,
          before: AdminExceptionFollowupCursor.parse(cursor.toJson()),
        ),
      );
      expect(
        query.hashCode,
        AdminExceptionFollowupDirectoryQuery(limit: 2, before: cursor).hashCode,
      );
      expect(const AdminExceptionFollowupDirectoryQuery().parameters, {
        'p_limit': 25,
        'p_before_created_at': null,
        'p_before_operator_id': null,
      });
      for (final limit in [0, 26]) {
        expect(
          () => AdminExceptionFollowupDirectoryQuery(limit: limit).parameters,
          throwsFormatException,
        );
      }
      expect(
        () => cursor.toJson()['operator_id'] = _other,
        throwsUnsupportedError,
      );
    },
  );
  test(
    'descending timestamp and UUID ties form monotonic unique directory pages',
    () {
      final first = AdminExceptionFollowupDirectory.parse(
            _directory(),
            query: _query,
          ),
          nextQuery = AdminExceptionFollowupDirectoryQuery(
            limit: 2,
            before: first.nextCursor,
          ),
          nextRaw = _directory()
            ..['rows'] = [
              _operator(
                _assignee,
                'Collect ID 500003',
                '2026-10-01T12:00:00.000000Z',
              ),
            ]
            ..['next_cursor'] = null;
      final next = AdminExceptionFollowupDirectory.parse(
        nextRaw,
        query: nextQuery,
      );
      expect(next.rows.single.operatorId, _assignee);
      expect(next.nextCursor, isNull);
      expect(
        () => AdminExceptionFollowupDirectory.parse(
          _directory(),
          query: nextQuery,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'directory rejects oversized pages private fields labels cursor drift and ordering',
    () {
      final raw = _directory();
      final variants = <Map<String, dynamic>>[
        {...raw, 'contract_version': 2.0},
        {...raw, 'scope': 'collection'},
        {...raw, 'limit': 1},
        {...raw, 'limit': 2.0},
        {...raw, 'authorization': 'PRIVATE_CANARY'},
        {...raw, 'sample_valid_until': _at},
        {
          ...raw,
          'rows': [...raw['rows'] as List, (raw['rows'] as List).first],
        },
        {...raw, 'rows': (raw['rows'] as List).reversed.toList()},
        {
          ...raw,
          'rows': [(raw['rows'] as List).first, (raw['rows'] as List).first],
        },
        {
          ...raw,
          'rows': [(raw['rows'] as List).first],
        },
        {
          ...raw,
          'next_cursor': {
            'created_at': '2026-10-01T12:00:00.000001Z',
            'operator_id': _actor,
          },
        },
        {
          ...raw,
          'next_cursor': {
            'created_at': '2026-10-01T12:00:00.000000Z',
            'operator_id': _assignee,
          },
        },
      ];
      for (final row in variants) {
        expect(
          () => AdminExceptionFollowupDirectory.parse(row, query: _query),
          throwsFormatException,
        );
      }
      for (final patch in [
        {'display_label': 'PRIVATE_CANARY@example.com'},
        {'display_label': 'Collect ID 250780000000'},
        {'display_label': 'Collect ID 500001\n'},
        {'operator_id': 'PRIVATE_CANARY'},
        {'created_at': '2026-10-01T12:30:10.000001Z'},
        {'phone': 'PRIVATE_CANARY'},
      ]) {
        final value = _copy(raw), rows = value['rows'] as List;
        rows[0] = {...rows[0] as Map<String, dynamic>, ...patch};
        expect(
          () => AdminExceptionFollowupDirectory.parse(value, query: _query),
          throwsFormatException,
        );
      }
      for (final key in raw.keys) {
        expect(
          () => AdminExceptionFollowupDirectory.parse(
            {...raw}..remove(key),
            query: _query,
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'empty directory is explicit and never fabricates an eligible operator',
    () {
      final raw = _directory()
            ..['rows'] = []
            ..['next_cursor'] = null,
          directory = AdminExceptionFollowupDirectory.parse(raw, query: _query);
      expect(directory.rows, isEmpty);
      expect(directory.nextCursor, isNull);
      expect(directory.isEligible(_actor, DateTime.parse(_at)), isFalse);
    },
  );
}
