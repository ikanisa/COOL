import 'package:collect_app/admin/core/admin_entity_audit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/admin_entity_audit_fixture.dart';

void main() {
  for (final name in [
    'shadow',
    'expiry',
    'gateway',
    'supervisor',
    'exception',
    'receipt',
  ]) {
    test('strict DTO accepts synthetic $name action data without renewal', () {
      final raw = auditObserved(name), query = auditQuery(auditObserved(name));
      final snapshot = AdminEntityAuditSnapshot.parse(raw, query: query);
      expect(snapshot.query.kind.wire, raw['entity_kind']);
      expect(
        snapshot.checkedAt.toIso8601String(),
        DateTime.parse(raw['checked_at'] as String).toIso8601String(),
      );
      expect(
        snapshot.rows.map((row) => row.requestId),
        (raw['rows'] as List).map((row) => (row as Map)['request_id']),
      );
      expect(
        snapshot.rows.map((row) => row.actorId),
        (raw['rows'] as List).map((row) => (row as Map)['actor_id']),
      );
      expect(snapshot.nextCursor, isNull);
      expect(
        snapshot.validUntil.difference(snapshot.checkedAt),
        const Duration(seconds: 60),
      );
    });
  }
  test(
    'current read expires at its exact boundary while old action time stays historical',
    () {
      final raw = auditObserved();
      final snapshot = AdminEntityAuditSnapshot.parse(
        raw,
        query: auditQuery(raw),
      );
      expect(
        snapshot.isFresh(
          snapshot.checkedAt.subtract(const Duration(seconds: 5)),
        ),
        true,
      );
      expect(
        snapshot.isFresh(
          snapshot.checkedAt.subtract(const Duration(microseconds: 5000001)),
        ),
        false,
      );
      expect(
        snapshot.isFresh(
          snapshot.validUntil.subtract(const Duration(microseconds: 1)),
        ),
        true,
      );
      expect(snapshot.isFresh(snapshot.validUntil), false);
      expect(snapshot.rows.last.recordedAt.isBefore(snapshot.checkedAt), true);
    },
  );
  final corruptions = <String, void Function(Map<String, dynamic>)>{
    'extra private diagnostic': (raw) => raw['private'] = 'PRIVATE_CANARY',
    'wrong version': (raw) => raw['contract_version'] = 2,
    'fractional version': (raw) => raw['contract_version'] = 1.0,
    'wrong scope': (raw) => raw['scope'] = 'tenant',
    'wrong kind': (raw) => raw['entity_kind'] = 'receipt',
    'wrong identity': (raw) =>
        raw['entity_id'] = '99810000-0000-4000-8000-000000000001',
    'wrong echoed limit': (raw) => raw['limit'] = 21,
    'fractional echoed limit': (raw) => raw['limit'] = 20.0,
    'unknown status': (raw) => raw['status'] = 'healthy',
    'unavailable with actions': (raw) => raw['status'] = 'unavailable',
    'history completeness claim': (raw) => raw['history_complete'] = true,
    'historical backfill claim': (raw) =>
        raw['historical_shadow_audit_backfilled'] = true,
    'financial claim': (raw) => raw['financial_action'] = true,
    'send claim': (raw) => raw['send_action'] = true,
    'string false': (raw) => raw['send_action'] = 'false',
    'invalid leap day': (raw) => raw['checked_at'] = '2026-02-29T00:00:00Z',
    'non UTC timestamp': (raw) =>
        raw['checked_at'] = '2026-10-01T00:00:00+02:00',
    'shorter TTL': (raw) => raw['sample_valid_until'] = DateTime.parse(
      raw['checked_at'] as String,
    ).add(const Duration(seconds: 59)).toIso8601String(),
    'longer TTL': (raw) => raw['sample_valid_until'] = DateTime.parse(
      raw['checked_at'] as String,
    ).add(const Duration(seconds: 61)).toIso8601String(),
    'rows object': (raw) => raw['rows'] = {},
    'duplicate action IDs': (raw) => (raw['rows'] as List).add(
      auditCopy((raw['rows'] as List).first as Map<String, dynamic>),
    ),
    'reversed chronological order': (raw) =>
        raw['rows'] = (raw['rows'] as List).reversed.toList(),
    'cursor without a full page': (raw) => raw['next_cursor'] = {
      'recorded_at': (raw['rows'] as List).last['recorded_at'],
      'event_id': (raw['rows'] as List).last['event_id'],
    },
  };
  for (final entry in corruptions.entries) {
    test('${entry.key} cannot become action evidence', () {
      final original = auditObserved(), raw = auditCopy(original);
      entry.value(raw);
      expect(
        () => AdminEntityAuditSnapshot.parse(raw, query: auditQuery(original)),
        throwsFormatException,
      );
    });
  }
  final eventCorruptions = <String, Object?>{
    'source': 'receipt_cancellation',
    'action': 'receipt.cancel_unstarted',
    'actor_id': 'unknown actor',
    'request_id': 'upper-invalid',
    'event_id': 'ABCDEF00-0000-4000-8000-000000000001',
    'recorded_at': '2100-01-01T00:00:00Z',
    'revision': 1,
    'fence_version': 0,
    'reason_code': 'operator_cancelled',
    'message_body': 'PRIVATE_CANARY',
  };
  for (final entry in eventCorruptions.entries) {
    test(
      'malformed event ${entry.key} fails the exact source relationship',
      () {
        final original = auditObserved(), raw = auditCopy(original);
        ((raw['rows'] as List).first as Map)[entry.key] = entry.value;
        expect(
          () =>
              AdminEntityAuditSnapshot.parse(raw, query: auditQuery(original)),
          throwsFormatException,
        );
      },
    );
  }
  for (final name in ['gateway', 'supervisor', 'exception', 'receipt']) {
    test('$name original action IDs and nonnullable actor stay bound', () {
      final original = auditObserved(name);
      for (final patch in [
        {'actor_id': null},
        {'event_id': '99810000-0000-4000-8000-000000000099'},
      ]) {
        final raw = auditCopy(original);
        ((raw['rows'] as List).first as Map).addAll(patch);
        expect(
          () =>
              AdminEntityAuditSnapshot.parse(raw, query: auditQuery(original)),
          throwsFormatException,
        );
      }
    });
  }
  test(
    'shadow may explicitly retain a missing actor without inventing one',
    () {
      final original = auditObserved(), raw = auditCopy(original);
      ((raw['rows'] as List).first as Map)['actor_id'] = null;
      expect(
        AdminEntityAuditSnapshot.parse(
          raw,
          query: auditQuery(original),
        ).rows.first.actorId,
        isNull,
      );
    },
  );
  test('exception and receipt reasons cannot cross their private sources', () {
    for (final name in ['exception', 'receipt']) {
      final original = auditObserved(name), raw = auditCopy(original);
      ((raw['rows'] as List).first as Map)['reason_code'] = name == 'exception'
          ? 'operator_cancelled'
          : 'review_started';
      expect(
        () => AdminEntityAuditSnapshot.parse(raw, query: auditQuery(original)),
        throwsFormatException,
      );
    }
  });
  test('cursor pages retain strict boundary and the last shown event', () {
    final original = auditObserved();
    final firstQuery = auditQuery(original, limit: 1);
    final first = AdminEntityAuditSnapshot.parse(
      auditWindow(original, firstQuery),
      query: firstQuery,
    );
    expect(first.nextCursor, first.rows.single.cursor);
    final secondQuery = auditQuery(
      original,
      limit: 1,
      before: first.nextCursor,
    );
    final second = AdminEntityAuditSnapshot.parse(
      auditWindow(original, secondQuery),
      query: secondQuery,
    );
    expect(second.rows.single.eventId, isNot(first.rows.single.eventId));
    expect(
      second.rows.single.cursor.compareTo(first.rows.single.cursor),
      lessThan(0),
    );
    expect(
      () => AdminEntityAuditSnapshot.parse(
        auditWindow(original, firstQuery),
        query: secondQuery,
      ),
      throwsFormatException,
    );
    final malformed = auditWindow(original, firstQuery);
    (malformed['next_cursor'] as Map)['event_id'] =
        '99810000-0000-4000-8000-000000000099';
    expect(
      () => AdminEntityAuditSnapshot.parse(malformed, query: firstQuery),
      throwsFormatException,
    );
  });
  test(
    'equal timestamp ordering uses exact descending UUID keyset tie break',
    () {
      final original = auditObserved(), raw = auditCopy(original);
      final rows = raw['rows'] as List;
      final time = (rows.first as Map)['recorded_at'];
      for (var i = 0; i < rows.length; i++) {
        (rows[i] as Map)
          ..['recorded_at'] = time
          ..['event_id'] = '99810000-0000-4000-8000-00000000000${3 - i}';
      }
      expect(
        AdminEntityAuditSnapshot.parse(raw, query: auditQuery(original)).rows,
        hasLength(3),
      );
      raw['rows'] = rows.reversed.toList();
      expect(
        () => AdminEntityAuditSnapshot.parse(raw, query: auditQuery(original)),
        throwsFormatException,
      );
    },
  );
  test(
    'unavailable and empty available reads remain distinct and incomplete',
    () {
      final original = auditObserved(),
          raw = auditCopy(original)..['rows'] = [];
      expect(
        AdminEntityAuditSnapshot.parse(
          raw,
          query: auditQuery(original),
        ).available,
        true,
      );
      raw['status'] = 'unavailable';
      expect(
        AdminEntityAuditSnapshot.parse(
          raw,
          query: auditQuery(original),
        ).available,
        false,
      );
    },
  );
  test('query rejects bad IDs, bounds and invalid UTC years before use', () {
    final raw = auditObserved(), query = auditQuery(raw);
    for (final limit in [0, 51]) {
      expect(
        () => AdminEntityAuditQuery(
          kind: query.kind,
          id: query.id,
          limit: limit,
        ).validate(),
        throwsFormatException,
      );
    }
    expect(
      () => AdminEntityAuditQuery(kind: query.kind, id: 'bad').validate(),
      throwsFormatException,
    );
    expect(
      () => AdminEntityAuditQuery(
        kind: query.kind,
        id: query.id,
        before: AdminEntityAuditCursor(
          recordedAt: DateTime.utc(10000),
          eventId: query.id,
        ),
      ).validate(),
      throwsFormatException,
    );
  });
}
