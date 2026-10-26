import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'member_data_authority_test.dart' as authority;
import 'payment_support_review_test.dart' as support;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('collect/payment_help_pending');
  final protectedValues = <String, String>{};
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    protectedValues.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = call.arguments as Map;
          final owner = args['owner_id'] as String;
          switch (call.method) {
            case 'read':
              return protectedValues[owner];
            case 'write':
              protectedValues[owner] = args['value'] as String;
              return true;
            case 'clear':
              protectedValues.remove(owner);
              return true;
          }
          throw StateError('Unexpected protected operation');
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  Map<String, Object?> result(http.Request request, String status) {
    final body = jsonDecode(request.body) as Map;
    return {
      'id': body['p_request_id'],
      'status': status,
      'collection_id': body['p_collection_id'],
      'intent_id': body['p_intent_id'],
      'financial_effects': 0,
    };
  }

  test(
    'replacement sign-in status read retains exact command and late commit reconciles 409',
    () async {
      final posts = <http.Request>[];
      var lateCommit = false;
      final h = await authority.Harness.create((request) {
        if (request.url.path.endsWith('/create_mobile_support_request')) {
          posts.add(request);
          if (posts.length == 1) {
            throw http.ClientException('Lost original reply');
          }
          lateCommit = true;
          return http.Response('{}', 409);
        }
        return authority.jsonResponse(
          result(request, lateCommit ? 'received' : 'absent'),
        );
      });
      h.repo.state = h.repo.state.copyWith(
        paymentIntents: [support.paymentIntent()],
      );
      await expectLater(
        h.repo.requestPaymentHelp(
          intentId: support.intentId,
          note: 'Original durable evidence',
        ),
        throwsA(isA<http.ClientException>()),
      );
      final firstBody = posts.single.body;
      await h.login(authority.actor, authority.nextSession);
      h.repo.state = h.repo.state.copyWith(
        paymentIntents: [support.paymentIntent()],
      );
      final received = await h.repo.requestPaymentHelp(
        intentId: support.intentId,
        note: 'Changed UI draft must not replace original',
      );
      expect(received.received, isTrue);
      expect(posts, hasLength(2));
      expect(posts.last.body, firstBody);
      expect(
        posts.last.headers['Authorization'],
        'Bearer ${authority.jwt(authority.actor, authority.nextSession)}',
      );
      expect(
        (await h.repo.paymentHelpForIntent(support.intentId))!.received,
        isTrue,
      );
      expect(
        h.repo.state.paymentIntents.single.hasCommittedContribution,
        isFalse,
      );
    },
  );

  test(
    'unknown or foreign status cannot authorize another send or claim Received',
    () async {
      for (final invalid in [
        {'status': 'unknown'},
        {'id': authority.other},
        {'collection_id': authority.other},
        {'intent_id': authority.other},
        {'financial_effects': 1},
        {'financial_effects': null},
      ]) {
        protectedValues.clear();
        var first = true;
        final posts = <http.Request>[];
        final h = await authority.Harness.create((request) {
          if (request.url.path.endsWith('/create_mobile_support_request')) {
            posts.add(request);
            throw http.ClientException('Lost reply');
          }
          if (first) {
            first = false;
            return http.Response('{}', 503);
          }
          return authority.jsonResponse({
            ...result(request, 'absent'),
            ...invalid,
          });
        });
        h.repo.state = h.repo.state.copyWith(
          paymentIntents: [support.paymentIntent()],
        );
        await expectLater(
          h.repo.requestPaymentHelp(intentId: support.intentId),
          throwsA(isA<http.ClientException>()),
        );
        await expectLater(
          h.repo.requestPaymentHelp(intentId: support.intentId),
          throwsFormatException,
        );
        expect(posts, hasLength(1));
        expect(
          (await h.repo.paymentHelpForIntent(support.intentId))!.received,
          isFalse,
        );
      }
    },
  );

  test('late status acknowledgement is rejected after owner changes', () async {
    final entered = Completer<void>(), reply = Completer<http.Response>();
    var statusReads = 0;
    var posts = 0;
    final h = await authority.Harness.create((request) {
      if (request.url.path.endsWith('/create_mobile_support_request')) {
        ++posts;
        throw http.ClientException('Lost reply');
      }
      if (++statusReads == 1) return http.Response('{}', 503);
      entered.complete();
      return reply.future;
    });
    h.repo.state = h.repo.state.copyWith(
      paymentIntents: [support.paymentIntent()],
    );
    await expectLater(
      h.repo.requestPaymentHelp(intentId: support.intentId),
      throwsA(isA<http.ClientException>()),
    );
    final request = h.repo.requestPaymentHelp(intentId: support.intentId);
    final rejected = expectLater(request, throwsStateError);
    await entered.future;
    final statusRequest = h.requests.last;
    await h.login(authority.other, authority.nextSession);
    reply.complete(authority.jsonResponse(result(statusRequest, 'received')));
    await rejected;
    expect(posts, 1);
    expect(protectedValues.containsKey(authority.actor), isFalse);
    expect(h.repo.state.currentProfile!.id, authority.other);
  });
  test(
    'received-only recovery never claims a replacement draft was accepted after cleanup',
    () async {
      final posts = <http.Request>[];
      final h = await authority.Harness.create((request) {
        if (request.url.path.endsWith('/create_mobile_support_request')) {
          posts.add(request);
          if (posts.length == 1) {
            throw http.ClientException('Lost original receipt');
          }
          return http.Response('{}', 409);
        }
        if (posts.length == 1 && protectedValues.isNotEmpty) {
          return http.Response('{}', 503);
        }
        return authority.jsonResponse(result(request, 'received'));
      });
      h.repo.state = h.repo.state.copyWith(
        paymentIntents: [support.paymentIntent()],
      );
      await expectLater(
        h.repo.requestPaymentHelp(
          intentId: support.intentId,
          providerReference: 'Original reference A',
          note: 'Original server evidence A',
        ),
        throwsA(isA<http.ClientException>()),
      );
      final original = jsonDecode(posts.single.body) as Map;
      // Explicit local account cleanup does not delete an already committed
      // server request. Its deterministic identity must still be recovered.
      protectedValues.clear();
      final received = await h.repo.requestPaymentHelp(
        intentId: support.intentId,
        providerReference: 'Replacement reference B',
        note: 'Unaccepted replacement draft B',
      );
      expect(received.requestId, original['p_request_id']);
      expect(received.received, isTrue);
      expect(received.reference, isNull);
      expect(received.note, isNull);
      expect(() => received.command, throwsStateError);
      final restored = (await h.repo.paymentHelpForIntent(support.intentId))!;
      expect(restored.received, isTrue);
      expect(protectedValues.values.single, isNot(contains('replacement')));
      expect(
        h.repo.state.paymentIntents.single.hasCommittedContribution,
        isFalse,
      );
    },
  );
}
