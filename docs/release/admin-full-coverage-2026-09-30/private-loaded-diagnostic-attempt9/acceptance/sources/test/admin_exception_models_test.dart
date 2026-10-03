import 'dart:convert';
import 'dart:io';
import 'package:collect_app/admin/core/admin_exception_models.dart';
import 'package:collect_app/admin/core/admin_exception_checkpoint.dart';
import 'package:collect_app/admin/core/admin_action_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> exceptionFixture([
  String name = 'populated',
]) => Map<String, dynamic>.from(
  jsonDecode(
        File(
          'docs/release/collect-codex-goal-2026-09-30/exception-reads-v2/backend-uat/observed-$name.json',
        ).readAsStringSync(),
      )
      as Map,
);
Map<String, dynamic> exceptionCopy(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
String exceptionUtc(DateTime value) {
  final iso = value.toUtc().toIso8601String();
  return RegExp(r'\.\d{3}Z$').hasMatch(iso)
      ? '${iso.substring(0, iso.length - 1)}000Z'
      : iso;
}

AdminExceptionSnapshot parseList(Map<String, dynamic> value) =>
    AdminExceptionSnapshot.parse(
      value,
      active: value['active'] as bool,
      limit: value['limit'] as int,
      source: value['source_kind'] == null
          ? null
          : AdminExceptionSource.parse(value['source_kind']),
    );
AdminExceptionIntent receiptIntent(Map<String, dynamic> receipt) =>
    AdminExceptionIntent(
      requestId: receipt['request_id'] as String,
      exceptionId: receipt['exception_id'] as String,
      revision: receipt['revision'] as int,
      action: AdminExceptionAction.parse(receipt['action']),
      reason: AdminExceptionReviewReason.reviewStarted,
    );

void main() {
  for (final name in ['empty', 'populated', 'filtered', 'cleared']) {
    test('actual isolated SQL $name list passes exact v2 parser', () {
      final raw = exceptionFixture(name);
      final parsed = parseList(raw);
      expect(parsed.rows.length, (raw['rows'] as List).length);
      expect(parsed.isFresh(parsed.checkedAt), isTrue);
      expect(parsed.isFresh(parsed.validUntil), isFalse);
    });
  }
  for (final name in ['recorded-lookup', 'unknown-lookup', 'progress-lookup']) {
    test('actual isolated SQL $name passes actor-bound v2 parser', () {
      final raw = exceptionFixture(name);
      final parsed = AdminExceptionLookup.parse(
        raw,
        requestId: raw['request_id'] as String,
      );
      expect(parsed.status, raw['status']);
      expect(parsed.receipt != null, raw['status'] == 'recorded');
      expect(parsed.isFresh(parsed.validUntil), isFalse);
    });
  }
  test(
    'actual v1 immutable action binds exact original UUID revision and action',
    () {
      final raw = exceptionFixture('action-receipt');
      final intent = receiptIntent(raw);
      expect(
        AdminExceptionReceipt.parse(raw, intent: intent).matches(intent),
        isTrue,
      );
      validateAdminActionReceipt(
        'admin_act_operational_exception_v1',
        intent.parameters,
        raw,
      );
      expect(
        () => validateAdminActionReceipt('admin_act_operational_exception_v1', {
          ...intent.parameters,
          'p_expected_revision': intent.revision + 1,
        }, raw),
        throwsFormatException,
      );
    },
  );
  test(
    'typed linkage never interchanges payment allocation and raw SMS IDs',
    () {
      final rows = parseList(exceptionFixture()).rows;
      final linked = rows
          .where(
            (row) =>
                row.source == AdminExceptionSource.payment &&
                row.transactionSmsId != null,
          )
          .single;
      expect(
        linked.investigationPath,
        '/admin/transactions/momo:${linked.transactionSmsId}',
      );
      expect(linked.transactionSmsId, isNot(linked.sourceId));
      final unlinked = rows
          .where(
            (row) =>
                row.source == AdminExceptionSource.payment &&
                row.transactionSmsId == null,
          )
          .single;
      expect(unlinked.investigationPath, isNull);
      final receipt = rows.singleWhere(
        (row) => row.source == AdminExceptionSource.receipt,
      );
      expect(
        receipt.investigationPath,
        '/admin/sms-receipts/${receipt.sourceId}',
      );
      expect(
        rows
            .singleWhere((row) => row.source == AdminExceptionSource.gateway)
            .investigationPath,
        '/admin/sms-gateway',
      );
    },
  );
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'extra private field': (raw) => raw['private_payload'] = 'PRIVATE_CANARY',
    'wrong version': (raw) => raw['contract_version'] = 1,
    'floating version': (raw) => raw['contract_version'] = 2.0,
    'wrong scope': (raw) => raw['scope'] = 'rwanda_momo',
    'fake complete scan': (raw) => raw['source_scan_complete'] = true,
    'fake delivery proof': (raw) => raw['escalation_delivery_verified'] = true,
    'wrong TTL': (raw) => raw['sample_valid_until'] = raw['checked_at'],
    'noncanonical timestamp': (raw) =>
        raw['checked_at'] = '2026-09-30T23:32:02Z',
    'impossible timestamp': (raw) =>
        raw['checked_at'] = '2026-02-30T23:32:02.085762Z',
    'extra row field': (raw) =>
        (raw['rows'] as List).first['actor_name'] = 'PRIVATE_CANARY',
    'unknown reason': (raw) =>
        (raw['rows'] as List).first['reason_code'] = 'SENT',
    'wrong reason category': (raw) =>
        (raw['rows'] as List).first['reason_code'] = 'CONTACT_MISSING',
    'fake receipt SMS link': (raw) =>
        (raw['rows'] as List)[1]['transaction_sms_id'] =
            (raw['rows'] as List).last['source_id'],
    'wrong raw SMS link': (raw) =>
        (raw['rows'] as List).last['transaction_sms_id'] =
            (raw['rows'] as List).first['source_id'],
    'integer string revision': (raw) =>
        (raw['rows'] as List).first['revision'] = '1',
    'revision beyond cap': (raw) =>
        (raw['rows'] as List).first['revision'] = 1000000001,
    'source time after check': (raw) =>
        (raw['rows'] as List).first['last_changed_at'] =
            raw['sample_valid_until'],
    'duplicate exception': (raw) =>
        (raw['rows'] as List).add((raw['rows'] as List).last),
    'wrong order': (raw) =>
        raw['rows'] = (raw['rows'] as List).reversed.toList(),
    'cursor without full page': (raw) => raw['next_cursor'] = {
      'changed_at': (raw['rows'] as List).last['last_changed_at'],
      'id': (raw['rows'] as List).last['id'],
    },
    'mixed active filter': (raw) =>
        (raw['rows'] as List).first['active'] = false,
  };
  for (final entry in mutations.entries) {
    test('strict list rejects ${entry.key}', () {
      final raw = exceptionFixture();
      entry.value(raw);
      expect(
        () => AdminExceptionSnapshot.parse(raw, active: true, limit: 50),
        throwsFormatException,
      );
    });
  }
  test(
    'filter echo and paired cursor are exact and keyset excludes newest rows',
    () {
      final raw = exceptionFixture();
      expect(
        () => AdminExceptionSnapshot.parse(raw, active: false, limit: 50),
        throwsFormatException,
      );
      expect(
        () => AdminExceptionSnapshot.parse(
          raw,
          active: true,
          limit: 50,
          source: AdminExceptionSource.gateway,
        ),
        throwsFormatException,
      );
      final rows = raw['rows'] as List;
      expect(
        () => AdminExceptionSnapshot.parse(
          raw,
          active: true,
          limit: 50,
          beforeChangedAt: DateTime.parse(
            rows.first['last_changed_at'] as String,
          ),
          beforeId: rows.first['id'] as String,
        ),
        throwsFormatException,
      );
      expect(
        () => AdminExceptionSnapshot.parse(
          raw,
          active: true,
          limit: 50,
          beforeId: rows.first['id'] as String,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'lookup wrong target and inconsistent outcome never return a receipt',
    () {
      final raw = exceptionFixture('recorded-lookup');
      expect(
        () => AdminExceptionLookup.parse(
          raw,
          requestId: '00000000-0000-0000-0000-000000000000',
        ),
        throwsFormatException,
      );
      raw['status'] = 'not_recorded';
      expect(
        () => AdminExceptionLookup.parse(
          raw,
          requestId: raw['request_id'] as String,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'checkpoint contains only bounded reviewed references and binds authenticated owner',
    () {
      final intent = receiptIntent(exceptionFixture('action-receipt'));
      final owner = adminExceptionOwnerDigest('synthetic-user');
      final encoded = AdminExceptionCheckpoint(owner, intent).encode();
      expect(encoded, isNot(contains('synthetic-user')));
      expect(encoded, isNot(contains('synthetic-session')));
      expect(jsonDecode(encoded).keys.toSet(), {
        'version',
        'owner_digest',
        'request',
      });
      expect(
        AdminExceptionCheckpoint.parse(encoded, owner).intent.parameters,
        intent.parameters,
      );
      expect(
        () => AdminExceptionCheckpoint.parse(
          encoded,
          adminExceptionOwnerDigest('different-user'),
        ),
        throwsFormatException,
      );
      final extra = jsonDecode(encoded) as Map..['token'] = 'PRIVATE_CANARY';
      expect(
        () => AdminExceptionCheckpoint.parse(jsonEncode(extra), owner),
        throwsFormatException,
      );
      expect(
        () => AdminExceptionCheckpoint.parse('x' * 2049, owner),
        throwsFormatException,
      );
      final mutated = jsonDecode(encoded) as Map;
      (mutated['request'] as Map)['p_reason_code'] = 'free text';
      expect(
        () => AdminExceptionCheckpoint.parse(jsonEncode(mutated), owner),
        throwsFormatException,
      );
    },
  );
}
