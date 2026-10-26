import 'dart:async';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'cloudflare_evidence_test_support.dart';

void main() {
  for (final area in CloudflareCoreArea.values) {
    test(
      '${area.name} consumes the actual isolated Worker/D1 v2 response',
      () async {
        final body = evidenceFixture(area.name);
        final repo = await evidenceRepository((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/admin/core/${area.name}');
          return evidenceResponse(body);
        });
        final result = await repo.list(area.rpcName);
        expect(result.total, body['total']);
        expect(result.rows.length, (body['rows'] as List).length);
        expect(
          result.rows.map((row) => row.id),
          (body['rows'] as List).map((row) => row['id']),
        );
      },
    );
  }

  test(
    'reversal preserves its negative sign and does not assert journal balance',
    () async {
      final repo = await evidenceRepository(
        (_) async => evidenceResponse(evidenceFixture('reversal_ledger')),
      );
      final result = await repo.list(
        CloudflareCoreArea.ledgers.rpcName,
        status: 'reversal',
      );
      final row = result.rows.single;
      expect(row.status, 'reversal');
      expect(row.amount.startsWith('-'), isTrue);
      expect(row.extra['signed_amount_rwf'], lessThan(0));
      expect(row.extra['amount_rwf'], -(row.extra['signed_amount_rwf'] as int));
      expect(row.extra['reverses_entry_id'], isNotNull);
      expect(row.extra.containsKey('balanced'), isFalse);
      expect(row.extra['provider_confirmation'], isFalse);
      expect(row.extra['settlement_status'], 'not_asserted');
    },
  );

  test(
    'overview uses retained evidence and actual net contributions after reversal',
    () async {
      final body = evidenceFixture('after_reversal');
      final repo = await evidenceRepository(
        (_) async => evidenceResponse(body),
      );
      final metrics = await repo.overviewMetrics();
      expect(metrics, hasLength(18));
      expect(
        metrics
            .firstWhere((m) => m.label == 'Net recorded contributions')
            .value,
        (body['amounts'] as Map)['total_net_contributions_rwf'],
      );
      expect(
        metrics.firstWhere((m) => m.label == 'Recorded evidence amount').value,
        (body['amounts'] as Map)['total_recorded_rwf'],
      );
      expect(
        metrics.any(
          (m) => m.label.contains('journal') || m.label.contains('settled'),
        ),
        isFalse,
      );
    },
  );

  for (final change in [
    'wrong_version',
    'wrong_model',
    'balanced_journal',
    'debit_credit',
    'positive_reversal',
    'zero_entry',
    'settlement_claim',
  ]) {
    test(
      'rejects $change instead of projecting unsupported financial authority',
      () async {
        final body = evidenceFixture('reversal_ledger');
        final row = (body['rows'] as List).single as Map<String, dynamic>;
        switch (change) {
          case 'wrong_version':
            body['contract_version'] = 1;
          case 'wrong_model':
            body['model'] = 'balanced_journal';
          case 'balanced_journal':
            row['balanced'] = true;
          case 'debit_credit':
            row['debit_rwf'] = 5000;
            row['credit_rwf'] = 5000;
          case 'positive_reversal':
            row['signed_amount_rwf'] = row['amount_rwf'];
            row['amount'] = '${row['amount_rwf']}';
          case 'zero_entry':
            row['signed_amount_rwf'] = 0;
            row['amount_rwf'] = 0;
            row['amount'] = '0';
          case 'settlement_claim':
            row['provider_confirmation'] = true;
            row['settlement_status'] = 'settled';
        }
        final repo = await evidenceRepository(
          (_) async => evidenceResponse(body),
        );
        await expectLater(
          repo.list(CloudflareCoreArea.ledgers.rpcName),
          throwsFormatException,
        );
      },
    );
  }

  test(
    'does not invent source network or payment settlement from retained evidence',
    () async {
      final body = evidenceFixture('transactions');
      final row = (body['rows'] as List).single as Map<String, dynamic>;
      row['network'] = null;
      row['payee_label'] = '';
      final repo = await evidenceRepository(
        (_) async => evidenceResponse(body),
      );
      final result = await repo.list(CloudflareCoreArea.transactions.rpcName);
      expect(result.rows.single.extra['network'], isNull);
      expect(result.rows.single.extra['source_network'], isNull);
      expect(result.rows.single.extra['evidence_level'], 'operator_recorded');
      row['provider_confirmation'] = true;
      await expectLater(
        repo.list(CloudflareCoreArea.transactions.rpcName),
        throwsFormatException,
      );
    },
  );

  test(
    'legacy journal basis is rejected and denied permissions never request records',
    () async {
      final body = evidenceFixture('overview');
      body['contribution_basis'] = 'confirmation_recorded_allocations';
      final repo = await evidenceRepository(
        (_) async => evidenceResponse(body),
      );
      await expectLater(repo.overviewMetrics(), throwsFormatException);
      var requests = 0;
      final denied = await evidenceRepository((_) async {
        requests++;
        return evidenceResponse(evidenceFixture('ledgers'));
      }, permissions: ['overview.read']);
      await expectLater(
        denied.list(CloudflareCoreArea.ledgers.rpcName),
        throwsA(isA<AdminAccountException>()),
      );
      expect(requests, 0);
    },
  );

  test(
    'session replacement discards an in-flight canonical response',
    () async {
      final pending = Completer<http.Response>();
      final repo = await evidenceRepository((_) => pending.future);
      final request = repo.list(CloudflareCoreArea.ledgers.rpcName);
      final assertion = expectLater(
        request,
        throwsA(isA<AdminAccountException>()),
      );
      repo.session.clear();
      pending.complete(evidenceResponse(evidenceFixture('ledgers')));
      await assertion;
    },
  );
}
