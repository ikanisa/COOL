import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_execution_models.dart';
import 'support/execution_fixture.dart';

void main() {
  test(
    'embedded real RPC fixture bytes match all12 retained SQL producer hashes',
    () {
      expect(
        sha256.convert(utf8.encode(notMaterializedRaw)).toString(),
        '06476ab5ec94e5cf71094da874924286356c5cb0aeacb6866b83941870f86ade',
      );
      expect(
        sha256.convert(utf8.encode(unarmedRaw)).toString(),
        '2192d76eedbd4fd66998e1b52c2682bff203d1208ded8d5caad41ce2add3b0af',
      );
      expect(
        sha256.convert(utf8.encode(armedUnknownRaw)).toString(),
        'a8af4ad60993b5153722e95446b2f9fca2354311184a85bafe70b15861b5bfa0',
      );
      expect(
        sha256.convert(utf8.encode(knownEmptyPageRaw)).toString(),
        '8689dcfc25e36d93c4be61bbd353e42c1284485e01d27410632d653afb7dce8e',
      );
      expect(
        sha256.convert(utf8.encode(unavailableRaw)).toString(),
        '06dde6d1ac735278ee24cc0471cc8cf0356aa7883c2114a0de7af53d54a093fb',
      );
      expect(
        sha256.convert(utf8.encode(unavailablePageRaw)).toString(),
        'e710f8b408e77582d7771971d52f1ead76064603bbf20b322685458619c21c47',
      );
      expect(
        sha256.convert(utf8.encode(knownSentRaw)).toString(),
        '3437a802eda0dd6a800c71652fc1bffb3e07f5fa75cf1a7eb95198bf0bfb0be5',
      );
      expect(
        sha256.convert(utf8.encode(fixedPagesRaw)).toString(),
        '91251ad6216c37b7fe10ddea2f5f223dbefb24a347ed6b2e9ade9ef2c4f4510d',
      );
      expect(
        sha256.convert(utf8.encode(maxPageRaw)).toString(),
        '994f06fbd7a3a239de33c846ad839d1ebadccaae5171154b963dceee4851a770',
      );
      expect(
        sha256.convert(utf8.encode(archivedRaw)).toString(),
        'ab65596e42ca9ea2a2ebfc3b1719ba031dac9acc8e2e2a863af16e6c590fa22e',
      );
      expect(
        sha256.convert(utf8.encode(lateUncertainRaw)).toString(),
        '92c93f6fc7c025fdbb92945a9178741251f4af7cd0983efc408923cd131ca0b4',
      );
      expect(
        sha256.convert(utf8.encode(revokedRaw)).toString(),
        'ffab0a70d5749e30de7f93bb99fa88911cb460b6500ff7b3f0ac04fe332e6fee',
      );
    },
  );

  test(
    'exact retained real v4 summary producers decode every available execution state and journal ACK',
    () {
      for (final raw in [
        notMaterializedRaw,
        unarmedRaw,
        armedUnknownRaw,
        knownSentRaw,
        archivedRaw,
        lateUncertainRaw,
        revokedRaw,
      ]) {
        final value = snapshot(raw);
        expect(value.available, isTrue);
        expect(value.execution!['observation_count'], isNull);
        expect(value.row['financial_action'], isFalse);
        expect(value.row['delivery_proven'], isFalse);
      }
      expect(snapshot(unavailableRaw).available, isFalse);
      expect(snapshot(lateUncertainRaw).state, 'uncertain');
      expect(
        snapshot(archivedRaw).execution!['archive'],
        snapshot(lateUncertainRaw).execution!['archive'],
      );
    },
  );
  test(
    'exact real fixed pages retain unique ordered callback identities and enforce snapshot attempt',
    () {
      final f = ExecutionFixture();
      int? after;
      final ids = <String>{};
      for (final raw in f.pages) {
        final p = AdminReceiptSuccessorObservationPage.parse(
          raw,
          f.original,
          after,
          10,
        );
        expect(p.available, isTrue);
        for (final row in p.items) {
          expect(ids.add(row['request_id'] as String), isTrue);
        }
        after = p.next;
      }
      expect(ids.length, greaterThan(50));
      expect(after, isNull);
      final empty = decoded(knownEmptyPageRaw), current = snapshot(unarmedRaw);
      expect(
        AdminReceiptSuccessorObservationPage.parse(
          empty,
          current,
          null,
          20,
        ).items,
        isEmpty,
      );
    },
  );
  test(
    'summary decoder refuses extra keys unsafe totals route drift arm and time contradictions',
    () {
      final base = decoded(knownSentRaw),
          approval = base['approval_id'] as String,
          root = base['primary_receipt_id'] as String;
      final mutations = <void Function(Map<String, dynamic>)>[
        (r) => r['extra'] = true,
        (r) => r['contract_version'] = 3,
        (r) => r['delivery_proven'] = true,
        (r) => r['execution']['observation_count'] = 0,
        (r) => r['execution']['route']['primary_receipt_id'] =
            '00000000-0000-0000-0000-000000000001',
        (r) => r['execution']['route']['approval_id'] =
            '00000000-0000-0000-0000-000000000001',
        (r) => r['execution']['route']['dispatch_job_id'] = root,
        (r) => r['execution']['arm'] = null,
        (r) => r['execution']['latest_projection'] = null,
        (r) => r['execution']['latest_projection']['state'] = 'uncertain',
        (r) => r['execution']['attempt']['expires_at'] =
            r['execution']['attempt']['issued_at'],
        (r) => r['execution']['attempt']['segment_count'] = 11,
        (r) => r['execution']['execution_events'][1]['lineage_before'] = 1,
        (r) => r['execution']['execution_events'][1]['approval_request_id'] =
            '00000000-0000-0000-0000-000000000001',
        (r) => r['sample_valid_until'] = r['checked_at'],
      ];
      for (final mutate in mutations) {
        final r = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
        mutate(r);
        expect(
          () => AdminReceiptSuccessorExecutionSnapshot.parse(r, approval, root),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'page decoder refuses changed cutoff cursor duplicate order hidden authority and attempt alias',
    () {
      final f = ExecutionFixture(), base = f.pages.first;
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (r) => r['cutoff_revision'] = (r['cutoff_revision'] as int) + 1,
        (r) => r['after_revision'] = 1,
        (r) => r['send_action'] = true,
        (r) => r['items'][0]['attempt_id'] =
            '00000000-0000-0000-0000-000000000001',
        (r) => r['items'][1] = r['items'][0],
        (r) => r['next_after_revision'] = 1,
        (r) => r['items'][0]['body'] = 'Unrequested content',
        (r) => r['items'][0]['segment_index'] = 10,
      ]) {
        final r = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
        mutate(r);
        expect(
          () => AdminReceiptSuccessorObservationPage.parse(
            r,
            f.original,
            null,
            10,
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'validated DTO snapshots deeply freeze nested callback routes and preserve freshness boundary',
    () {
      final r = decoded(archivedRaw),
          s = AdminReceiptSuccessorExecutionSnapshot.parse(
            r,
            r['approval_id'] as String,
            r['primary_receipt_id'] as String,
          );
      final route = s.execution!['route'] as Map,
          original = route['dispatch_job_id'];
      r['execution']['route']['dispatch_job_id'] = 'changed';
      expect(route['dispatch_job_id'], original);
      expect(
        () => route['dispatch_job_id'] = 'changed',
        throwsUnsupportedError,
      );
      expect(s.fresh(s.checkedAt), isTrue);
      expect(s.fresh(s.validUntil), isFalse);
    },
  );
}
