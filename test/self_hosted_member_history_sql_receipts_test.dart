@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/models/member_history_page.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

// This current additive-profile packet is produced by actual local PostgreSQL
// and shipping domain handlers. It is deliberately not a current14/16 receipt.
const _packetPath = String.fromEnvironment('SELFHOST_HISTORY_PACKET');
const _packetSha = String.fromEnvironment('SELFHOST_HISTORY_PACKET_SHA256');
const _inputsPath = String.fromEnvironment('SELFHOST_HISTORY_INPUTS');
const _inputsSha = String.fromEnvironment('SELFHOST_HISTORY_INPUTS_SHA256');
const _sqlPath = String.fromEnvironment('SELFHOST_HISTORY_SQL');
const _sqlSha = String.fromEnvironment('SELFHOST_HISTORY_SQL_SHA256');
const _sourceSha = String.fromEnvironment('SELFHOST_HISTORY_SOURCE_SHA256');
const _profile = 'reviewed_current_chain_member_history_v3';

Map<String, dynamic> _object(Object? value) =>
    Map<String, dynamic>.from(value! as Map);

MemberHistoryPage _page(Map<String, dynamic> value) {
  final rows = value['items'];
  if (value['contract_version'] != 2 ||
      rows is! List ||
      rows.length > 50 ||
      rows.any((row) => row is! Map)) {
    throw const FormatException('Expected a bounded current signed SQL page');
  }
  return MemberHistoryPage.fromJson(value, [
    for (final row in rows) Contribution.historyEventFromJson(_object(row)),
  ]);
}

MemberHistoryQuery _query(Map<String, dynamic> value) => MemberHistoryQuery(
  collectionId: value['collection_id'] as String?,
  search: value['search'] as String,
  sort: value['sort'] as String,
);

void main() {
  late Map<String, dynamic> packet, inputs;
  late List<Map<String, dynamic>> pages, requests, statements;
  setUpAll(() {
    if ([
      _packetPath,
      _packetSha,
      _inputsPath,
      _inputsSha,
      _sqlPath,
      _sqlSha,
      _sourceSha,
    ].any((value) => value.isEmpty)) {
      throw StateError(
        'Run the current self-hosted native history capture and supply its '
        'reviewed DEFINES.json. Historical CURRENT14_* defines are incompatible.',
      );
    }
    for (final pair in [
      (_packetPath, _packetSha),
      (_inputsPath, _inputsSha),
      (_sqlPath, _sqlSha),
    ]) {
      expect(
        sha256.convert(File(pair.$1).readAsBytesSync()).toString(),
        pair.$2,
      );
    }
    packet = _object(jsonDecode(File(_packetPath).readAsStringSync()));
    inputs = _object(jsonDecode(File(_inputsPath).readAsStringSync()));
    pages = (packet['pages'] as List).map(_object).toList();
    requests = (packet['requests'] as List).map(_object).toList();
    statements = (jsonDecode(File(_sqlPath).readAsStringSync()) as List)
        .map(_object)
        .toList();
  });

  test(
    'current additive receipt binds exact SQL and executing Dart source',
    () {
      expect(packet['format'], 'collect.selfhost.actual-member-history-sql.v3');
      expect(packet['profile'], _profile);
      expect(inputs['format'], 'collect.selfhost.history.inputs.v3');
      expect(inputs['profile'], _profile);
      expect(packet['source_inputs_sha256'], _inputsSha);
      expect(packet['source_sha256'], _sourceSha);
      expect(inputs['source_sha256'], _sourceSha);
      final files = (inputs['files'] as List).map(_object).toList();
      expect(
        sha256.convert(utf8.encode(jsonEncode(files))).toString(),
        _sourceSha,
      );
      final roles = <String>{};
      for (final pin in files) {
        final role = pin['role'] as String;
        expect(role.startsWith('/'), isFalse);
        expect(
          role.split('/').any((part) => part == '..' || part.isEmpty),
          isFalse,
        );
        expect(roles.add(role), isTrue);
        final source = File(role).readAsBytesSync();
        expect(source.length, pin['bytes'], reason: role);
        expect(sha256.convert(source).toString(), pin['sha256'], reason: role);
      }
      expect(
        roles,
        containsAll({
          'supabase/functions/_shared/domain/member_history.js',
          'supabase/functions/_shared/domain/member_history_sql.js',
          'lib/shared/models/member_history_page.dart',
          'lib/shared/models/member_history_signed.dart',
          'lib/shared/models/collect_payment_json.dart',
          'lib/core/data/exact_json_values.dart',
          'test/self_hosted_member_history_sql_receipts_test.dart',
        }),
      );
      final fixture = _object(packet['fixture']);
      expect(fixture['baseline'], 'current16');
      expect(fixture['historical_packet'], isFalse);
      expect(fixture['synthetic_only'], isTrue);
      expect(fixture['postgres_major'], 17);
      expect(fixture['normal_runtime_role'], 'collect_runtime');
      expect(fixture['owner_superuser'], isFalse);
      expect(fixture['financial_rows_directly_seeded'], isTrue);
      expect(fixture['financial_posting_acceptance'], isFalse);
      final currentManifest = _object(
        jsonDecode(
          File('deploy/self-hosted/migrations.lock.json').readAsStringSync(),
        ),
      );
      expect(currentManifest['format'], 'collect.selfhost.migrations.v1');
      expect(currentManifest['original_count'], 16);
      final currentMigrations = (currentManifest['migrations'] as List)
          .map(_object)
          .toList();
      expect(fixture['migration_count'], currentMigrations.length);
      expect(fixture['complete_reviewed_chain'], isTrue);
      expect(fixture['deployment_binding_acceptance'], isFalse);
      final additions = (fixture['additive_migrations'] as List)
          .map(_object)
          .toList();
      expect(
        additions.map((row) => row['name']).toList(),
        currentMigrations.skip(16).map((row) => row['name']).toList(),
      );
      for (final addition in additions) {
        expect(
          files.singleWhere(
            (pin) => pin['role'] == 'supabase/migrations/${addition['name']}',
          )['sha256'],
          addition['sha256'],
        );
      }
      expect(packet['provider_calls'], 0);
      expect(packet['hosted_acceptance'], isFalse);
      expect(packet['managed_auth_acceptance'], isFalse);
      expect(packet['production_acceptance'], isFalse);
      expect(packet['actual_runtime_transactions_commit'], isTrue);
      expect(packet['SQL_statement_count'], statements.length);
      expect(statements, isNotEmpty);
      for (final native in (packet['runtime_identities'] as List).map(
        _object,
      )) {
        expect(native['current_role'], 'collect_runtime');
        expect(native['session_role'], 'postgres');
        expect(native['edge_verified'], 'true');
      }
    },
  );

  test('actual SQL windows decode with exact totals, scope and privacy', () {
    expect(pages.length, greaterThanOrEqualTo(15));
    var empty = 0;
    for (final window in pages) {
      final response = _object(window['response']);
      final requestId = window['request_id'] as int;
      expect(_object(requests[requestId]['response'])['status'], 200);
      expect(_object(requests[requestId]['response'])['body'], response);
      expect(
        statements.any(
          (row) =>
              row['request_id'] == requestId &&
              (row['sql'] as String).contains('WITH authority AS MATERIALIZED'),
        ),
        isTrue,
      );
      final decoded = _page(response);
      decoded.validateRequest(
        query: _query(_object(window['query'])),
        cursor: window['requested_cursor'] == null
            ? null
            : _object(window['requested_cursor']),
        limit: window['limit'] as int,
      );
      expect(decoded.isSignedHistory, isTrue);
      if (decoded.totalCount == 0) empty++;
      for (final raw in (response['items'] as List).map(_object)) {
        expect(raw['provider_confirmation'], isFalse);
        expect(raw['settlement_status'], 'not_asserted');
        for (final forbidden in [
          'transaction_id',
          'phone',
          'email',
          'raw_body',
          'external_reference',
          'payer_display_name',
        ]) {
          expect(raw.containsKey(forbidden), isFalse, reason: forbidden);
        }
      }
    }
    expect(empty, greaterThanOrEqualTo(2));
  });

  test('large actual pages append correctly in every supported sort', () {
    final sorts = <String>{};
    for (final second in pages.where(
      (row) => row['requested_cursor'] != null,
    )) {
      final current = _page(_object(second['response']));
      if (current.totalCount != 10005) continue;
      final query = _query(_object(second['query']));
      final first = pages.lastWhere(
        (row) =>
            row['requested_cursor'] == null &&
            _object(row['response'])['next_cursor'] != null &&
            jsonEncode(_object(row['response'])['next_cursor']) ==
                jsonEncode(second['requested_cursor']),
      );
      final combined = _page(
        _object(first['response']),
      ).append(current, query: query);
      expect(combined.totalCount, 10005);
      expect(combined.items.length, 100);
      expect(combined.items.map((row) => row.id).toSet(), hasLength(100));
      expect(combined.nextCursor, isNotNull);
      expect(combined.totals, current.totals);
      expect(combined.ownTotals, current.ownTotals);
      sorts.add(query.sort);
    }
    expect(sorts, {'newest', 'oldest', 'highest', 'lowest'});
  });

  test('complete half-open date range preserves totals and end cursor', () {
    final windows = pages
        .where((row) => _object(row['query'])['from'] != null)
        .toList();
    expect(windows, hasLength(2));
    final first = _page(_object(windows.first['response']));
    final last = _page(_object(windows.last['response']));
    final combined = first.append(
      last,
      query: _query(_object(windows.first['query'])),
    );
    expect(combined.items.length, 60);
    expect(combined.totalCount, 60);
    expect(combined.nextCursor, isNull);
    final scope = _object(windows.first['query']);
    final from = DateTime.parse(scope['from'] as String);
    final before = DateTime.parse(scope['before'] as String);
    for (final item in combined.items) {
      expect(item.createdAt.isUtc, isTrue);
      expect(item.createdAt.isBefore(from), isFalse);
      expect(item.createdAt.isBefore(before), isTrue);
    }
    expect(
      combined.items.fold<int>(0, (total, row) => total + row.amountMinor),
      combined.totals['RWF'],
    );
  });

  test('actual balances agree with complete history aggregates', () {
    final large = _page(
      _object(
        pages.firstWhere(
          (row) => _object(row['response'])['total_count'] == 10005,
        )['response'],
      ),
    );
    final balance = CollectionSummary.fromJson(
      _object((packet['balances'] as List).single),
    );
    expect(balance.amountRaisedMinor, large.totals['RWF']);
    expect(balance.currentUserBalanceMinor, large.ownTotals['RWF']);
    expect(balance.supporterCount, 2);
  });

  test(
    'native invalid ranges, stale cursors and revoked sessions stay refused',
    () {
      final refused = requests
          .map((row) => _object(row['response']))
          .where((row) => row['status'] != 200)
          .toList();
      expect(
        refused.where(
          (row) =>
              row['status'] == 400 &&
              _object(row['body'])['code'] == 'invalid_history_range',
        ),
        hasLength(3),
      );
      expect(
        refused.where(
          (row) =>
              row['status'] == 409 &&
              _object(row['body'])['code'] == 'history_changed',
        ),
        hasLength(2),
      );
      expect(
        refused.where(
          (row) =>
              row['status'] == 403 &&
              _object(row['body'])['code'] == 'session_changed',
        ),
        hasLength(1),
      );
      for (final response in refused) {
        expect(() => _page(_object(response['body'])), throwsFormatException);
      }
    },
  );
}
