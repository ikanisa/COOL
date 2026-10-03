import 'dart:convert';

import 'package:collect_app/admin/core/admin_roster_import.dart';
import 'package:collect_app/admin/core/admin_roster_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/admin_roster_fixture.dart';

class _StagedGateway extends FakeRosterGateway {
  _StagedGateway(this.expiry, {this.previewExpiry});
  final Object? expiry;
  final String? previewExpiry;
  final calls = <String>[];
  late Map<String, dynamic> staged;
  @override
  bool get supportsRecovery => true;
  @override
  Future<Object?> prepare(Map<String, dynamic> request) async {
    await super.prepare(request);
    if (previewExpiry != null) {
      latest!['expires_at'] = previewExpiry;
    }
    return latest;
  }

  @override
  Future<Object?> recoveryRpc(String name, Map<String, dynamic> params) async {
    calls.add(name);
    if (name == 'admin_stage_roster_import_intent') {
      staged = params;
      return {
        'contract_version': 1,
        'ok': true,
        'import_id': rosterImportId,
        'expires_at': expiry,
        'request_id': params['p_request_id'],
        'kind': params['p_kind'],
        'payload_sha256': params['p_payload_sha256'],
      };
    }
    if (name == 'admin_execute_roster_import_intent') {
      final payload =
          jsonDecode(staged['p_payload'] as String) as Map<String, dynamic>;
      final result = previewFixture(
        body!,
        parent: latest,
        reviewed: payload['p_rows'] as List,
      );
      if (previewExpiry != null) {
        result['expires_at'] = previewExpiry;
      }
      latest = result;
      return {
        'contract_version': 1,
        'ok': true,
        'request_id': params['p_request_id'],
        'import_id': rosterImportId,
        'kind': staged['p_kind'],
        'payload_sha256': params['p_payload_sha256'],
        'result': result,
      };
    }
    throw StateError('Unexpected synthetic roster RPC');
  }
}

void main() {
  final body = AdminRosterUpload.pasted('Synthetic calendar roster').body;
  for (final value in [
    '2026-09-31T12:00:00Z',
    '2026-02-30T12:00:00Z',
    '2025-02-29T12:00:00Z',
    '2026-10-01T24:00:00Z',
    '2026-10-01T12:60:00Z',
    '2026-10-01T12:00:60Z',
    '2026-10-01T12:00:00+24:00',
    '2026-10-01T12:00:00+02:60',
    '2026-10-01T12:00:00.1234567Z',
    '0000-10-01T12:00:00Z',
    '0001-01-01T00:00:00+01:00',
    '9999-12-31T23:00:00-01:00',
  ]) {
    test('roster receipt rejects normalized or unsafe expiry $value', () {
      expect(
        () => AdminRosterPreview.fromJson(
          previewFixture(body)..['expires_at'] = value,
        ),
        throwsFormatException,
      );
    });
  }
  for (final value in [
    '2026-10-01T12:00:00Z',
    '2026-10-01T14:00:00+02:00',
    '2024-02-29T12:00:00.123456Z',
    '0001-01-01T00:00:00Z',
    '9999-12-31T23:59:59.999999Z',
  ]) {
    test('roster valid expiry retains its actual instant $value', () {
      final preview = AdminRosterPreview.fromJson(
        previewFixture(body)..['expires_at'] = value,
      );
      expect(preview.expiresAt, DateTime.parse(value).toUtc());
    });
  }
  for (final expiry in <Object?>[
    '2026-09-31T12:00:00Z',
    '2026-10-01T12:00:00.0000001Z',
    '2026-10-01T12:00:01Z',
    DateTime.utc(2026, 10, 1, 12),
    null,
  ]) {
    test(
      'invalid/mismatched staged expiry cannot execute review: $expiry',
      () async {
        final gateway = _StagedGateway(expiry);
        final draft = AdminRosterDraft(
          gateway,
          collectionId: rosterCollectionId,
        );
        addTearDown(draft.dispose);
        await draft.prepare(() async => AdminRosterUpload.pasted('Synthetic'));
        await draft.saveReview('Reviewed original source');
        expect(gateway.calls, ['admin_stage_roster_import_intent']);
        expect(draft.error, isNotNull);
        expect(draft.preview?.revisionNumber, 1);
      },
    );
  }
  test('equivalent zoned staged expiry accepts exact request ACK', () async {
    final gateway = _StagedGateway('2026-10-01T14:00:00+02:00');
    final draft = AdminRosterDraft(gateway, collectionId: rosterCollectionId);
    addTearDown(draft.dispose);
    await draft.prepare(() async => AdminRosterUpload.pasted('Synthetic'));
    await draft.saveReview('Reviewed original source');
    expect(gateway.calls, [
      'admin_stage_roster_import_intent',
      'admin_execute_roster_import_intent',
    ]);
    expect(draft.error, isNull);
    expect(draft.preview?.revisionNumber, 2);
  });
  // These fake-authority cases exercise exact ACK instants on VM and Chrome;
  // historical year controls do not assert a server would admit expired work.
  for (final values in [
    (
      '2026-10-01T12:00:00.123456Z',
      '2026-10-01T12:00:00.123457Z',
      '2026-10-01T14:00:00.123456+02:00',
    ),
    (
      '0001-01-01T00:00:00.000001Z',
      '0001-01-01T00:00:00.000002Z',
      '0001-01-01T01:00:00.000001+01:00',
    ),
    (
      '9999-12-31T23:59:59.999998Z',
      '9999-12-31T23:59:59.999999Z',
      '9999-12-31T23:59:59.999998+00:00',
    ),
  ]) {
    test('one microsecond ACK difference rejects ${values.$1}', () async {
      final gateway = _StagedGateway(values.$2, previewExpiry: values.$1);
      final draft = AdminRosterDraft(gateway, collectionId: rosterCollectionId);
      addTearDown(draft.dispose);
      await draft.prepare(() async => AdminRosterUpload.pasted('Synthetic'));
      await draft.saveReview('Reviewed original source');
      expect(gateway.calls, ['admin_stage_roster_import_intent']);
      expect(draft.error, isNotNull);
      expect(draft.preview?.revisionNumber, 1);
    });
    test('same microsecond zoned ACK accepts ${values.$1}', () async {
      final gateway = _StagedGateway(values.$3, previewExpiry: values.$1);
      final draft = AdminRosterDraft(gateway, collectionId: rosterCollectionId);
      addTearDown(draft.dispose);
      await draft.prepare(() async => AdminRosterUpload.pasted('Synthetic'));
      await draft.saveReview('Reviewed original source');
      expect(gateway.calls, [
        'admin_stage_roster_import_intent',
        'admin_execute_roster_import_intent',
      ]);
      expect(draft.error, isNull);
      expect(draft.preview?.revisionNumber, 2);
    });
  }
}
