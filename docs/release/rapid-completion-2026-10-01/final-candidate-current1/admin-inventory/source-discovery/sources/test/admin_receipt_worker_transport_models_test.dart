import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_receipt_worker_transport_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _root =
    'docs/release/collect-codex-goal-2026-09-30/'
    'receipt-worker-transport-health-20261001/accepted-sql-attempt5';
Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('$_root/observed-detail-$name.json').readAsStringSync())
        as Map<String, dynamic>;
Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
AdminReceiptWorkerTransport _parse(Map<String, dynamic> value) =>
    AdminReceiptWorkerTransport.parse(
      value,
      requestId: value['request_id'] as String,
      expectedExpiresAt: DateTime.parse(value['original_expires_at'] as String),
    );
const _otherId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

void main() {
  for (final name in [
    'absent',
    'accepted',
    'auth',
    'authority',
    'bad_json',
    'config-refused',
    'conflict',
    'contradictory',
    'duplicate_response',
    'endpoint',
    'exact_conflict',
    'expired-fenced',
    'expired-unknown',
    'invalid',
    'network',
    'not-collected',
    'original-recorded',
    'oversized',
    'pending',
    'queued',
    'quota',
    'rate',
    'redirect',
    'refused',
    'request',
    'schema-unavailable',
    'server',
    'timeout',
  ]) {
    test(
      'actual SQL $name preserves HTTP facts and separate original evidence',
      () {
        final raw = _fixture(name);
        final view = _parse(raw);
        expect(view.originalStatus, raw['original_status']);
        expect(view.originalReceiptStatus, raw['original_receipt_status']);
        expect(view.scanRequestId, raw['scan_request_id']);
        expect(view.rows.first.outcome, raw['rows'][0]['outcome']);
        expect(
          view.rows.first.httpRequestId,
          raw['rows'][0]['http_request_id'],
        );
        expect(
          view.rows.first.transportTerminal,
          raw['rows'][0]['transport_terminal'],
        );
        expect(view.alerts, raw['alerts']);
        expect(view.originalStatusLabel, isNotEmpty);
        expect(view.rows.first.outcomeLabel, isNotEmpty);
        expect(view.isFresh(view.checkedAt), isTrue);
        expect(view.isFresh(view.validUntil), isFalse);
        expect(
          view.isFresh(view.checkedAt.subtract(const Duration(seconds: 6))),
          isFalse,
        );
        if (view.rows.first.outcome == 'HTTP_ACCEPTED' &&
            name != 'original-recorded') {
          expect(view.originalReceiptStatus, isNull);
        }
      },
    );
  }
  test(
    'request ID and immutable expiry bind investigation to its selected original',
    () {
      final raw = _fixture('accepted');
      expect(
        () => AdminReceiptWorkerTransport.parse(
          raw,
          requestId: _otherId,
          expectedExpiresAt: DateTime.parse(
            raw['original_expires_at'] as String,
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => AdminReceiptWorkerTransport.parse(
          raw,
          requestId: raw['request_id'] as String,
          expectedExpiresAt: DateTime.parse(
            raw['original_expires_at'] as String,
          ).add(const Duration(microseconds: 1)),
        ),
        throwsFormatException,
      );
      expect(
        () => AdminReceiptWorkerTransport.parse(
          raw,
          requestId: 'PRIVATE_CANARY',
          expectedExpiresAt: DateTime.parse(
            raw['original_expires_at'] as String,
          ),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'every exact field is required and private field additions fail closed',
    () {
      final raw = _fixture('accepted');
      for (final key in raw.keys) {
        final changed = _copy(raw)..remove(key);
        expect(
          () => AdminReceiptWorkerTransport.parse(
            changed,
            requestId: raw['request_id'] as String,
            expectedExpiresAt: DateTime.parse(
              raw['original_expires_at'] as String,
            ),
          ),
          throwsFormatException,
        );
      }
      for (final section in ['rows', 'collector']) {
        final object = section == 'rows'
            ? raw['rows'][0] as Map
            : raw[section] as Map;
        for (final key in object.keys) {
          final changed = _copy(raw);
          (section == 'rows'
                  ? changed['rows'][0] as Map
                  : changed[section] as Map)
              .remove(key);
          expect(() => _parse(changed), throwsFormatException);
        }
      }
      for (final field in [
        'response_body',
        'url',
        'phone',
        'headers',
        'error_msg',
        'credential',
      ]) {
        for (final section in ['top', 'row', 'collector']) {
          final changed = _copy(raw);
          (section == 'top'
                  ? changed
                  : section == 'row'
                  ? changed['rows'][0] as Map
                  : changed['collector'] as Map)[field] =
              'PRIVATE_CANARY';
          expect(() => _parse(changed), throwsFormatException);
        }
      }
    },
  );
  test(
    'finite version states flags and typed collections reject unsupported claims',
    () {
      final raw = _fixture('accepted');
      for (final patch in [
        {'contract_version': 2},
        {'contract_version': 1.0},
        {'original_status': 'sent'},
        {'source_scan_complete': true},
        {'financial_action': true},
        {'send_action': true},
        {'resend_action': true},
        {'rows': {}},
        {'alerts': {}},
        {'original_receipt_status': 'completed'},
        {'scan_request_id': _otherId},
      ]) {
        expect(() => _parse({...raw, ...patch}), throwsFormatException);
      }
    },
  );
  test(
    'HTTP success cannot fabricate original completion or expiry recovery',
    () {
      final accepted = _fixture('accepted');
      expect(_parse(accepted).originalStatus, 'pending');
      for (final patch in [
        {'original_status': 'recorded'},
        {'original_status': 'unknown'},
        {'original_status': 'expired_without_receipt'},
        {
          'original_status': 'recorded',
          'original_receipt_status': 'completed',
          'scan_request_id': _otherId,
        },
      ]) {
        expect(() => _parse({...accepted, ...patch}), throwsFormatException);
      }
      final actual = _fixture('original-recorded');
      expect(_parse(actual).originalStatus, 'recorded');
      expect(
        () => _parse({...actual, 'original_receipt_status': 'sent'}),
        throwsFormatException,
      );
      expect(
        () => _parse({
          ..._fixture('expired-unknown'),
          'original_status': 'pending',
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'strict timestamps and exact sixty-second freshness reject shifted or invalid evidence',
    () {
      final raw = _fixture('accepted');
      for (final patch in [
        {'checked_at': '2026-10-01T00:00:00Z'},
        {'checked_at': '2026-13-01T00:00:00.000000Z'},
        {'sample_valid_until': raw['checked_at'] as String},
        {
          'sample_valid_until': DateTime.parse(
            raw['checked_at'] as String,
          ).add(const Duration(seconds: 61)).toIso8601String(),
        },
      ]) {
        expect(() => _parse({...raw, ...patch}), throwsFormatException);
      }
      final future = _copy(raw);
      future['rows'][0]['dispatched_at'] = DateTime.parse(
        raw['checked_at'] as String,
      ).add(const Duration(seconds: 6)).toIso8601String();
      expect(() => _parse(future), throwsFormatException);
    },
  );
  test(
    'decimal HTTP IDs preserve bigint precision and refuse alternate encodings',
    () {
      final raw = _fixture('accepted');
      final large = _copy(raw);
      large['rows'][0]['http_request_id'] = '9223372036854775807';
      expect(_parse(large).rows.first.httpRequestId, '9223372036854775807');
      for (final id in [
        1,
        '0',
        '-1',
        '01',
        '1e3',
        '9223372036854775808',
        'SECRET',
      ]) {
        final changed = _copy(raw);
        changed['rows'][0]['http_request_id'] = id;
        expect(() => _parse(changed), throwsFormatException);
      }
    },
  );
  test(
    'uncollected and unobserved evidence never invent a revision response or digest',
    () {
      final raw = _fixture('not-collected');
      for (final patch in [
        {'evidence_revision': 1},
        {'response_rows_observed': 0},
        {'http_status': 200},
        {'evidence_sha256': 'a' * 64},
        {'transport_terminal': true},
        {'worker_error_code': 'WORKER_AUTH_REQUIRED'},
        {'observed_at': raw['checked_at'] as String},
      ]) {
        final changed = _copy(raw);
        (changed['rows'][0] as Map).addAll(patch);
        expect(() => _parse(changed), throwsFormatException);
      }
      final queued = _fixture('queued');
      for (final patch in [
        {'response_rows_observed': 1},
        {'http_status': 200},
        {'transport_terminal': true},
      ]) {
        final changed = _copy(queued);
        (changed['rows'][0] as Map).addAll(patch);
        expect(() => _parse(changed), throwsFormatException);
      }
    },
  );
  test(
    'captured metadata refuses invalid digest revision response count and raw error',
    () {
      final raw = _fixture('accepted');
      for (final patch in [
        {'evidence_revision': 0},
        {'evidence_revision': 1.0},
        {'evidence_sha256': 'A' * 64},
        {'evidence_sha256': 'a' * 63},
        {'response_rows_observed': 2},
        {'http_status': 700},
        {'worker_error_code': 'SENSITIVE-NETWORK-ERROR'},
        {'transport_terminal': false},
        {'response_at': null},
        {'observed_at': null},
      ]) {
        final changed = _copy(raw);
        (changed['rows'][0] as Map).addAll(patch);
        expect(() => _parse(changed), throwsFormatException);
      }
    },
  );
  test(
    'finite classifications agree with the observed HTTP and worker error',
    () {
      final raw = _fixture('accepted');
      for (final outcome
          in AdminReceiptWorkerTransportAttempt.outcomeLabels.keys.where(
            (value) => !{'HTTP_ACCEPTED', 'RESPONSE_INVALID'}.contains(value),
          )) {
        final changed = _copy(raw);
        changed['rows'][0]['outcome'] = outcome;
        changed['alerts'] = [outcome];
        expect(() => _parse(changed), throwsFormatException);
      }
      final conflict = _fixture('exact_conflict');
      conflict['rows'][0]['worker_error_code'] = 'WORKER_UNCONFIGURED';
      expect(() => _parse(conflict), throwsFormatException);
      final config = _fixture('config-refused');
      config['rows'][0]['http_status'] = 200;
      expect(() => _parse(config), throwsFormatException);
    },
  );
  test(
    'attempt IDs order and ninety-second original authority constrain every row',
    () {
      final raw = _fixture('accepted');
      for (final attempts in [0, 2, 4]) {
        final changed = _copy(raw);
        changed['rows'][0]['attempt'] = attempts;
        expect(() => _parse(changed), throwsFormatException);
      }
      final duplicate = _copy(raw);
      duplicate['rows'].add(_copy(raw)['rows'][0]..['attempt'] = 2);
      expect(() => _parse(duplicate), throwsFormatException);
      final many = _copy(raw);
      many['rows'] = List.generate(4, (_) => _copy(raw)['rows'][0]);
      expect(() => _parse(many), throwsFormatException);
      final outside = _copy(raw);
      outside['rows'][0]['dispatched_at'] = DateTime.parse(
        raw['original_expires_at'] as String,
      ).subtract(const Duration(seconds: 91)).toIso8601String();
      expect(() => _parse(outside), throwsFormatException);
    },
  );
  test(
    'collector quotas preserve lowered caps and require actual redacted consistency',
    () {
      final raw = _fixture('quota');
      final view = _parse(raw);
      expect(view.collector.quotaExhausted, isTrue);
      for (final patch in [
        {'configuration_revision': 0},
        {'day_cap': 72001},
        {'day_inspections': -1},
        {'quota_exhausted': false},
        {'source_schema_valid': 'yes'},
        {'last_request_id': null},
        {'last_recorded_at': null},
      ]) {
        final changed = _copy(raw);
        (changed['collector'] as Map).addAll(patch);
        expect(() => _parse(changed), throwsFormatException);
      }
      final over = _copy(raw);
      over['collector']['day_inspections'] = view.collector.dayCap + 1;
      expect(_parse(over).collector.dayInspections, view.collector.dayCap + 1);
    },
  );
  test(
    'alert list derives from displayed latest attempt and actual collector evidence',
    () {
      final raw = _fixture('config-refused');
      for (final alerts in [
        [],
        ['SENT'],
        ['WORKER_CONFIG_REFUSED', 'WORKER_CONFIG_REFUSED'],
        ['WORKER_CONFIG_REFUSED', 'HTTP_ACCEPTED'],
      ]) {
        expect(() => _parse({...raw, 'alerts': alerts}), throwsFormatException);
      }
      final unobserved = _fixture('not-collected');
      unobserved['collector']['last_request_id'] = null;
      unobserved['collector']['last_recorded_at'] = null;
      unobserved['alerts'] = ['NOT_COLLECTED', 'COLLECTOR_UNOBSERVED'];
      expect(_parse(unobserved).collector.lastRecordedAt, isNull);
      final stale = _fixture('accepted');
      stale['collector']['last_recorded_at'] = DateTime.parse(
        stale['checked_at'] as String,
      ).subtract(const Duration(seconds: 181)).toIso8601String();
      stale['alerts'] = ['COLLECTOR_STALE'];
      expect(_parse(stale).alerts, ['COLLECTOR_STALE']);
    },
  );
  test(
    'retained response observations and consumer collections are immutable',
    () {
      final view = _parse(_fixture('config-refused'));
      expect(() => view.rows.clear(), throwsUnsupportedError);
      expect(() => view.alerts.clear(), throwsUnsupportedError);
      final before = _parse(_fixture('expired-unknown'));
      final fenced = _parse(_fixture('expired-fenced'));
      expect(
        before.rows.first.evidenceSha256,
        fenced.rows.first.evidenceSha256,
      );
      expect(before.originalStatus, 'unknown');
      expect(fenced.originalStatus, 'expired_without_receipt');
    },
  );
}
