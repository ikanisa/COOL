import 'dart:async';
import 'dart:convert';

import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'member_data_authority_test.dart' as authority;

const intentId = '70000000-0000-4000-8000-000000000001';
const requestId = '70000000-0000-4000-8000-000000000002';
PaymentIntentModel paymentIntent() => PaymentIntentModel(
  id: intentId,
  collectionId: authority.group,
  expectedAmountRwf: 5000,
  status: 'pending',
  createdAt: DateTime.utc(2026),
  expiresAt: DateTime.utc(2030),
);
Map<String, dynamic> acknowledgement() => {
  'id': requestId,
  'status': 'received',
  'collection_id': authority.group,
  'intent_id': intentId,
  'financial_effects': 0,
};
Future<String> request(CollectRepository repository) =>
    repository.createPaymentSupportReview(
      collectionId: authority.group,
      intentId: intentId,
      requestId: requestId,
      providerReference: '  SYNTHETIC-007  ',
      note: '  Synthetic retained payment evidence  ',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'payment help calls real RPC with captured authority and scoped receipt',
    () async {
      final harness = await authority.Harness.create(
        (_) => authority.jsonResponse(acknowledgement()),
      );
      harness.repo.state = harness.repo.state.copyWith(
        paymentIntents: [paymentIntent()],
      );
      final before = harness.repo.state.collectionSummaries;
      expect(await request(harness.repo), requestId);
      expect(
        harness.requests.single.url.path,
        '/v1/rpc/create_mobile_support_request',
      );
      expect(
        harness.requests.single.headers['Authorization'],
        'Bearer ${authority.jwt(authority.actor, authority.firstSession)}',
      );
      expect(jsonDecode(harness.requests.single.body), {
        'p_kind': 'payment_review',
        'p_collection_id': authority.group,
        'p_intent_id': intentId,
        'p_request_id': requestId,
        'p_provider_reference': 'SYNTHETIC-007',
        'p_note': 'Synthetic retained payment evidence',
      });
      expect(harness.repo.state.collectionSummaries, before);
      expect(
        harness.repo.state.paymentIntents.single.hasCommittedContribution,
        isFalse,
      );
    },
  );
  test('payment help cannot claim success without a live backend', () async {
    final repository = CollectRepository.fixture(
      initialState: authority
          .stateFor(authority.actor)
          .copyWith(paymentIntents: [paymentIntent()]),
    );
    addTearDown(repository.dispose);
    await expectLater(request(repository), throwsStateError);
  });
  test(
    'payment help rejects foreign or financially effective acknowledgements',
    () async {
      for (final invalid in [
        {'id': intentId},
        {'collection_id': authority.other},
        {'intent_id': requestId},
        {'status': 'credited'},
        {'financial_effects': 1},
        {'financial_effects': null},
      ]) {
        final harness = await authority.Harness.create(
          (_) => authority.jsonResponse({...acknowledgement(), ...invalid}),
        );
        harness.repo.state = harness.repo.state.copyWith(
          paymentIntents: [paymentIntent()],
        );
        await expectLater(request(harness.repo), throwsFormatException);
      }
    },
  );
  test(
    'late help acknowledgement cannot cross an authenticated session change',
    () async {
      final entered = Completer<void>(), reply = Completer<http.Response>();
      final harness = await authority.Harness.create((_) {
        entered.complete();
        return reply.future;
      });
      harness.repo.state = harness.repo.state.copyWith(
        paymentIntents: [paymentIntent()],
      );
      final pending = request(harness.repo);
      final failure = expectLater(pending, throwsStateError);
      await entered.future;
      await harness.login(authority.actor, authority.nextSession);
      reply.complete(authority.jsonResponse(acknowledgement()));
      await failure;
      expect(harness.requests.length, 1);
    },
  );
}
