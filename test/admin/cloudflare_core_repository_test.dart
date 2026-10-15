import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'cloudflare_core_fixtures.dart';

http.Response response(String body, int status) => http.Response.bytes(
  utf8.encode(body),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

Future<CloudflareAdminRepository> repository(
  Future<http.Response> Function(http.Request) respond, {
  List<String>? permissions,
}) async {
  final session = CloudflareAdminSession(
    MockClient((request) async {
      if (request.url.path.endsWith('/auth/session')) {
        return response(jsonEncode(coreSession(permissions: permissions)), 200);
      }
      return respond(request);
    }),
    origin: Uri.parse('https://admin.example.test/'),
  );
  addTearDown(session.dispose);
  await session.refresh();
  return CloudflareAdminRepository(session);
}

void main() {
  for (final area in CloudflareCoreArea.values) {
    test(
      '${area.name} maps only to bounded authenticated core GET and validates real row',
      () async {
        final repo = await repository((request) async {
          expect(request.method, 'GET');
          expect(request.url.origin, 'https://admin.example.test');
          expect(request.url.path, '/api/admin/core/${area.name}');
          expect(request.url.queryParameters, {
            'search': 'example',
            'status': '',
            'sort': 'created_at_asc',
            'limit': '25',
            'offset': '0',
            'country': 'RW',
          });
          return response(
            jsonEncode({
              'rows': [coreRow(area)],
              'total': 1,
            }),
            200,
          );
        });
        final result = await repo.list(
          area.rpcName,
          search: ' example ',
          sortBy: 'created_at_asc',
          countryCode: 'rw',
        );
        expect(result.total, 1);
        expect(result.rows.single.amount, coreRow(area)['amount']);
      },
    );
  }

  test('overview only exposes consistent measured source counts', () async {
    final repo = await repository((request) async {
      expect(request.url.path, '/api/admin/core/overview');
      return response(jsonEncode(coreOverview()), 200);
    });
    final result = await repo.overviewMetrics();
    expect(result, hasLength(19));
    expect(
      result.every(
        (metric) => metric.value == '0' && metric.status == 'measured',
      ),
      isTrue,
    );
  });

  test(
    'unsupported reads, writes, invalid filters and missing permissions never call transport',
    () async {
      var requests = 0;
      final repo = await repository((_) async {
        requests++;
        return response('{}', 200);
      }, permissions: ['overview.read']);
      await expectLater(
        repo.list('admin_list_collections'),
        throwsA(isA<AdminAccountException>()),
      );
      await expectLater(
        repo.list('admin_list_secret_users'),
        throwsUnsupportedError,
      );
      await expectLater(
        repo.action('create_group', {}),
        throwsUnsupportedError,
      );
      await expectLater(
        repo.list('admin_list_users', countryCode: 'MT'),
        throwsFormatException,
      );
      await expectLater(
        repo.list('admin_list_users', limit: 101),
        throwsFormatException,
      );
      await expectLater(
        repo.list('admin_list_users', status: 'admin'),
        throwsFormatException,
      );
      expect(requests, 0);
    },
  );

  test('signed-out and superseded requests cannot publish records', () async {
    final pending = Completer<http.Response>();
    final repo = await repository((_) => pending.future);
    final future = repo.list('admin_list_users');
    final assertion = expectLater(
      future,
      throwsA(isA<AdminAccountException>()),
    );
    repo.session.clear();
    pending.complete(response('{"rows":[],"total":0}', 200));
    await assertion;
    await expectLater(
      repo.list('admin_list_users'),
      throwsA(isA<AdminAccountException>()),
    );
  });

  test(
    'unavailable and malformed responses are never accepted as empty',
    () async {
      for (final response in [
        response('{}', 200),
        response('{"rows":[],"total":1}', 200),
        response('{"rows":[],"total":0}', 503),
        response('<html>Unavailable</html>', 200),
      ]) {
        final repo = await repository((_) async => response);
        await expectLater(
          repo.list('admin_list_users'),
          throwsA(anyOf(isA<FormatException>(), isA<AdminAccountException>())),
        );
      }
    },
  );

  test(
    'financial values, masks, page identity and overview consistency fail closed',
    () async {
      final cases = <(CloudflareCoreArea, Map<String, dynamic>)>[
        (CloudflareCoreArea.transactions, {'amount': 'RWF 4'}),
        (CloudflareCoreArea.transactions, {'amount_rwf': 9007199254740992}),
        (
          CloudflareCoreArea.transactions,
          {'allocated_amount_rwf': 9007199254740992},
        ),
        (
          CloudflareCoreArea.transactions,
          {'amount_rwf': 1, 'amount': '1', 'allocated_amount_rwf': 2},
        ),
        (CloudflareCoreArea.transactions, {'allocation_status': 'allocated'}),
        (CloudflareCoreArea.ledgers, {'balanced': true}),
        (CloudflareCoreArea.ledgers, {'debit_rwf': '100'}),
        (
          CloudflareCoreArea.ledgers,
          {'status': 'posted', 'posted_at': coreDate},
        ),
        (
          CloudflareCoreArea.payees,
          {'momo_masked': '0788123456', 'amount': '0788123456'},
        ),
        (
          CloudflareCoreArea.users,
          {'password_hash': 'never a directory field'},
        ),
        (CloudflareCoreArea.users, {'phone_masked': '0788123456'}),
        (
          CloudflareCoreArea.members,
          {'active_groups': 0, 'amount': '0 groups'},
        ),
        (CloudflareCoreArea.groups, {'country_code': 'MT'}),
        (CloudflareCoreArea.groups, {'created_at': '2026-15-99T00:00:00.000Z'}),
      ];
      for (final (area, change) in cases) {
        final row = coreRow(area)..addAll(change);
        final repo = await repository(
          (_) async => response(
            jsonEncode({
              'rows': [row],
              'total': 1,
            }),
            200,
          ),
        );
        await expectLater(
          repo.list(area.rpcName),
          throwsFormatException,
          reason: '${area.name}: ${change.keys}',
        );
      }
      final badOverview = coreOverview();
      (badOverview['metrics'] as List).first['value'] = '999';
      final repo = await repository(
        (_) async => response(jsonEncode(badOverview), 200),
      );
      await expectLater(repo.overviewMetrics(), throwsFormatException);
    },
  );

  test(
    'directory keeps authorized full contacts and leading-zero identity/code strings',
    () async {
      final repo = await repository(
        (_) async => response(
          jsonEncode({
            'rows': [coreRow(CloudflareCoreArea.users)],
            'total': 1,
          }),
          200,
        ),
      );
      final row = (await repo.list('admin_list_users')).rows.single;
      expect(row.title, '000123');
      expect(row.extra['public_id'], '000123');
      expect(row.extra['whatsapp_number'], '+250788001234');
      expect(row.extra['momo_number'], '0788001234');
      expect(row.extra['momo_pay_code'], '008000');
      expect(row.extra['total_contributed_rwf'], 5000);
    },
  );

  test(
    'Direct and operator-only people cannot invent WhatsApp or a linked profile',
    () async {
      final direct = coreRow(CloudflareCoreArea.users)
        ..addAll({
          'member_type': 'direct',
          'user_types': ['Direct'],
          'whatsapp_number': null,
        });
      final operator = coreRow(CloudflareCoreArea.users)
        ..addAll({
          'collect_user_id': null,
          'operator_admin_id': coreId,
          'operator_public_id': '000123',
          'operator_role': 'staff',
          'operator_status': 'revoked',
          'member_type': null,
          'user_types': ['Staff'],
          'whatsapp_number': null,
          'status': 'revoked',
          'account_status': 'revoked',
          'active_groups': 0,
          'amount': '0 groups',
        });
      final unknownApp = coreRow(CloudflareCoreArea.users)
        ..addAll({
          'display_name': null,
          'display_name_recorded': false,
          'name_verification': 'not_recorded',
        });
      for (final row in [direct, operator, unknownApp]) {
        final repo = await repository(
          (_) async => response(
            jsonEncode({
              'rows': [row],
              'total': 1,
            }),
            200,
          ),
        );
        final loaded = (await repo.list('admin_list_users')).rows.single;
        expect(loaded.extra['whatsapp_number'], row['whatsapp_number']);
        expect(loaded.extra['display_name'], row['display_name']);
      }
      for (final corrupt in [
        {
          'whatsapp_number': '+250788001234',
          'member_type': 'direct',
          'user_types': ['Direct'],
        },
        {'person_id': '22222222-2222-4222-8222-222222222222'},
        {
          'user_types': ['Admin', 'App'],
        },
        {'public_id': '12345'},
        {'momo_pay_code': '00ABC'},
        {'posted_contributed_rwf': 6000},
        {'display_name_recorded': false},
        {'display_name': null},
      ]) {
        final row = coreRow(CloudflareCoreArea.users)..addAll(corrupt);
        final repo = await repository(
          (_) async => response(
            jsonEncode({
              'rows': [row],
              'total': 1,
            }),
            200,
          ),
        );
        await expectLater(
          repo.list('admin_list_users'),
          throwsFormatException,
          reason: '${corrupt.keys}',
        );
      }
    },
  );

  test(
    'overview preserves exact aggregate decimal strings above web integer precision',
    () async {
      const total = '9223372036854775807';
      final body = coreOverview(amounts: {'total_collected_rwf': total});
      final repo = await repository(
        (_) async => response(jsonEncode(body), 200),
      );
      final metrics = await repo.overviewMetrics();
      expect(
        metrics
            .singleWhere((metric) => metric.label == 'Total collected')
            .value,
        total,
      );
      for (final value in ['-1', '1.2', '1e3', '01', 9223372036854775807]) {
        final invalid = coreOverview();
        invalid['amounts'] = {
          ...(invalid['amounts'] as Map),
          'total_collected_rwf': value,
        };
        final bad = await repository(
          (_) async => response(jsonEncode(invalid), 200),
        );
        await expectLater(bad.overviewMetrics(), throwsFormatException);
      }
    },
  );
  test(
    'transaction source lineage keeps public IDs immutable and rejects contradictory facts',
    () {
      const factId = '22222222-2222-4222-8222-222222222222';
      const reviewId = '33333333-3333-4333-8333-333333333333';
      final source = coreRow(CloudflareCoreArea.transactions)
        ..addAll({
          'transaction_reference': '234000123456789012',
          'title': '234000123456789012',
          'reference_payer_last3_known': true,
          'reference_payee_last3_known': true,
          'reference_source_fact_id': factId,
          'source_fact_id': factId,
          'source_link_basis': 'public_reference',
          'source_review_id': null,
          'source_kind': 'receiver',
          'parser_version': 'collect-sms-v1',
          'source_extraction_status': 'parsed',
          'source_body_sha256': 'a' * 64,
          'source_payload_sha256': 'b' * 64,
          'source_parsed_at': coreDate,
          'payer_name': 'ALICE QA',
          'payer_phone': '+250788001234',
          'payer_last3': '234',
          'payer_last3_known': true,
          'payee_momo_code': '008000',
          'provider_reference': 'QA-1234',
          'momo_transaction_reference': 'QA-1234',
          'momo_timestamp_local': '2026-10-05T12:35:45',
          'source_amount_rwf': 12500,
          'amount_rwf': 12500,
          'amount': '12500',
          'source_network': 'mtn_momo',
          'direction': 'incoming',
          'is_payment': true,
        });
      validateCloudflareTransactionFacts(source);
      final reviewed = {
        ...source,
        'transaction_reference': '000000123456789012',
        'title': '000000123456789012',
        'reference_payer_last3_known': false,
        'reference_payee_last3_known': false,
        'reference_source_fact_id': null,
        'source_kind': 'member',
        'source_link_basis': 'reviewed_member_receipt',
        'source_review_id': reviewId,
      };
      validateCloudflareTransactionFacts(reviewed);
      expect(
        reviewed['transaction_reference'],
        coreRow(CloudflareCoreArea.transactions)['transaction_reference'],
      );
      for (final corrupt in [
        {'source_link_basis': 'not_recorded'},
        {'source_review_id': reviewId},
        {'source_fact_id': reviewId},
        {'source_amount_rwf': null},
        {'source_amount_rwf': 12501},
        {'source_network': 'airtel_money'},
        {'momo_transaction_reference': 'WRONG-1234'},
        {'momo_timestamp_local': '2026-02-31T12:35:45'},
        {'momo_timezone_offset': '+14:30', 'timezone_known': true},
        {'payer_masked_phone': '***234'},
        {'payer_last3': '345'},
        {'direction': 'outgoing'},
        {'provider_confirmation': true},
        {'settlement_status': 'settled'},
      ]) {
        expect(
          () => validateCloudflareTransactionFacts({...source, ...corrupt}),
          throwsFormatException,
          reason: '$corrupt',
        );
      }
    },
  );
}
