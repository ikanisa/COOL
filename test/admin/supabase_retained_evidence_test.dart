import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../core/supabase_backend_test.dart' as fixtures;
import 'cloudflare_canonical_reconciliation_support.dart';

const evidenceId = '11111111-1111-4111-8111-111111111111';
const retainedText = 'Controlled private retained evidence π';
const reviewReason = 'Review the retained synthetic SMS source';
final retainedBytes = utf8.encode(retainedText);
final retainedDigest = sha256.convert(retainedBytes).toString();

Map<String, dynamic> protectedEvidenceSession({String? withoutPermission}) {
  final auth = canonicalSupabaseFinancialSession();
  final user = auth['user'] as Map;
  user['permissions'] = [
    ...(user['permissions'] as List).cast<String>(),
    'sms.read',
    'sms.reveal',
  ].where((value) => value != withoutPermission).toList();
  return auth;
}

Map<String, dynamic> currentEvidenceProof() => financialSupabaseEmailProof(
  DateTime.now().toUtc().subtract(const Duration(seconds: 1)).toIso8601String(),
);

http.Response retainedResponse({String? sensitivity = 'raw_sms'}) =>
    http.Response.bytes(
      retainedBytes,
      200,
      headers: {
        'content-type': 'text/plain; charset=utf-8',
        'x-collect-evidence-sensitivity': ?sensitivity,
      },
    );

Future<FinancialHarness> evidenceHarness({
  Map<String, dynamic>? auth,
  Map<String, dynamic>? proof,
  Future<http.Response> Function(http.Request)? reply,
}) => FinancialHarness.create(
  auth: auth ?? protectedEvidenceSession(),
  environment: fixtures.environment(),
  origin: Uri.parse('https://admin.collect.ikanisa.com'),
  emailVerification: proof ?? currentEvidenceProof(),
  reply: reply ?? (_) async => retainedResponse(),
);

Future<String> readEvidence(
  FinancialHarness harness, {
  Object? sensitivity,
  String? reason = reviewReason,
}) => harness.session.retainedEvidence(
  evidenceId,
  sha256Hex: retainedDigest,
  sizeBytes: retainedBytes.length,
  sourceSensitivity: sensitivity,
  reviewReason: reason,
);

Matcher deniedWith(String code) => throwsA(
  isA<CloudflareAdminRequestException>().having((e) => e.code, 'code', code),
);

void main() {
  test('source metadata is additive and unknown sources remain protected', () {
    final row = Map<String, dynamic>.from(
      (financialFixture('detail')['related']['evidence']['rows'] as List).single
          as Map,
    );
    for (final source in [null, 'unclassified', 'future_source', 7]) {
      final parsed = parseCanonicalRetainedEvidence({
        ...row,
        'source_sensitivity': ?source,
      }, row['id'] as String);
      expect(parsed['source_sensitivity'], 'unclassified');
      expect(
        retainedEvidenceRequiresReview(parsed['source_sensitivity']),
        isTrue,
      );
    }
    for (final source in ['ordinary', 'raw_sms']) {
      final parsed = parseCanonicalRetainedEvidence({
        ...row,
        'source_sensitivity': source,
      }, row['id'] as String);
      expect(parsed['source_sensitivity'], source);
      expect(retainedEvidenceRequiresReview(source), source != 'ordinary');
    }
  });

  for (final permission in ['sms.read', 'sms.reveal']) {
    test('protected evidence without $permission never sends a read', () async {
      var calls = 0;
      final h = await evidenceHarness(
        auth: protectedEvidenceSession(withoutPermission: permission),
        reply: (_) async {
          calls++;
          return retainedResponse();
        },
      );
      await expectLater(readEvidence(h), deniedWith('permission_required'));
      expect(calls, 0);
    });
  }

  for (final stale in [false, true]) {
    test(
      'protected evidence requires current Supabase email proof stale=$stale',
      () async {
        var calls = 0;
        final proof = financialSupabaseEmailProof(
          stale
              ? DateTime.now()
                    .toUtc()
                    .subtract(const Duration(minutes: 6))
                    .toIso8601String()
              : null,
        );
        final h = await evidenceHarness(
          proof: proof,
          reply: (_) async {
            calls++;
            return retainedResponse();
          },
        );
        expect(h.session.user!.usesEmailVerification, isTrue);
        expect(h.session.user!.assuranceLevel, 1);
        await expectLater(
          readEvidence(h),
          deniedWith('recent_email_sign_in_required'),
        );
        expect(calls, 0);
      },
    );
  }

  test('invalid, missing or control-bearing reasons never dispatch', () async {
    var calls = 0;
    final h = await evidenceHarness(
      reply: (_) async {
        calls++;
        return retainedResponse();
      },
    );
    for (final reason in [
      null,
      '',
      'short',
      'a' * 1001,
      'review\r\nheader',
      'review\u007freason',
    ]) {
      await expectLater(
        readEvidence(h, reason: reason),
        deniedWith('reason_required'),
      );
    }
    expect(calls, 0);
  });

  for (final sensitivity in [
    null,
    'raw_sms',
    'unclassified',
    'future_source',
  ]) {
    test(
      'protected $sensitivity evidence sends only the audited reason header',
      () async {
        final calls = <http.Request>[];
        final h = await evidenceHarness(
          reply: (request) async {
            calls.add(request);
            return retainedResponse();
          },
        );
        expect(
          await readEvidence(
            h,
            sensitivity: sensitivity,
            reason: '  $reviewReason  ',
          ),
          retainedText,
        );
        final request = calls.single;
        expect(request.method, 'GET');
        expect(request.url.query, isEmpty);
        expect(request.url.path, '/api/admin/evidence/$evidenceId');
        expect(request.headers['X-Collect-Review-Reason'], reviewReason);
        expect(request.headers.containsKey('Authorization'), isFalse);
        expect(
          request.headers.containsKey('X-Collect-Evidence-Sensitivity'),
          isFalse,
        );
        expect(request.body, isEmpty);
        expect(h.storage.values, isEmpty);
      },
    );
  }

  test(
    'positively ordinary evidence keeps its existing permission behavior',
    () async {
      final calls = <http.Request>[];
      final h = await evidenceHarness(
        auth: canonicalSupabaseFinancialSession(),
        proof: financialSupabaseEmailProof(null),
        reply: (request) async {
          calls.add(request);
          return retainedResponse(sensitivity: 'ordinary');
        },
      );
      expect(
        await readEvidence(h, sensitivity: 'ordinary', reason: null),
        retainedText,
      );
      expect(
        calls.single.headers.containsKey('X-Collect-Review-Reason'),
        isFalse,
      );
    },
  );

  for (final sensitivity in [
    null,
    'future_source',
    'raw_sms',
    'unclassified',
  ]) {
    test('ordinary metadata cannot release a $sensitivity response', () async {
      final h = await evidenceHarness(
        reply: (_) async => retainedResponse(sensitivity: sensitivity),
      );
      await expectLater(
        readEvidence(h, sensitivity: 'ordinary'),
        deniedWith('evidence_access_changed'),
      );
    });
  }

  test(
    'removing same-session email proof during a read releases no plaintext',
    () async {
      final held = Completer<http.Response>();
      final proof = currentEvidenceProof();
      final h = await evidenceHarness(proof: proof, reply: (_) => held.future);
      final before = h.session.authorityFence;
      final checked = expectLater(
        readEvidence(h),
        deniedWith('recent_email_sign_in_required'),
      );
      proof['emailVerifiedAt'] = null;
      await h.session.refresh();
      expect(h.session.authorityFence, before);
      held.complete(retainedResponse());
      await checked;
    },
  );

  test(
    'denied reads expose bounded public messages, never a server raw body',
    () async {
      for (final code in [
        'permission_required',
        'recent_email_sign_in_required',
        'reason_required',
        'evidence_integrity_failed',
      ]) {
        final h = await evidenceHarness(
          reply: (_) async => financialResponse({
            'error': {'code': code, 'message': 'PRIVATE RAW SMS BODY'},
            'details': 'PRIVATE RAW SMS BODY',
          }, code == 'reason_required' ? 400 : 403),
        );
        await expectLater(
          readEvidence(h),
          throwsA(
            isA<AdminAccountException>().having(
              (e) => e.message,
              'public copy',
              isNot(contains('PRIVATE')),
            ),
          ),
        );
      }
    },
  );
}
