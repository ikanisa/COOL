import 'dart:async';

import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/features/payments/contribution_flow_screen.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';

import '../fixtures/collect_repository_fixture.dart';
import '../shared/member_data_authority_test.dart' as authority;

class _InstantSms extends SmsAccessChannel {
  const _InstantSms();
  @override
  Future<bool> suspendUnlessOwner(String? currentUserId) async => true;
}

class _EmptyCache extends CollectOfflineCache {
  const _EmptyCache();
  @override
  Future<void> clear() async {}
}

class _FlowRepository extends FixtureCollectRepository {
  _FlowRepository(this.client)
    : super(
        backend: client,
        smsAccessChannel: const _InstantSms(),
        offlineCache: const _EmptyCache(),
        profileOverride: const CollectProfile(
          id: authority.actor,
          publicId: '123456',
          whatsappPhone: '+250788123456',
          countryCode: 'RW',
          currencyCode: 'RWF',
          momoProvider: 'mtn_momo',
          momoNumber: '0788123456',
        ),
      ) {
    seed = state;
  }
  final CollectCloudflareClient client;
  late CollectState seed;
  Completer<void>? nextLoad;
  int creates = 0;
  Future<PaymentIntentModel> Function(int)? respond;
  @override
  Future<void> loadInitial({bool syncPendingSms = false}) async {
    state = seed;
    nextLoad?.complete();
    nextLoad = null;
  }

  @override
  Future<PaymentIntentModel> createPaymentIntent(PaymentIntentDraft draft) {
    creates++;
    return respond?.call(creates) ?? Future.value(_intent());
  }
}

PaymentIntentModel _intent() => PaymentIntentModel(
  id: 'synthetic-flow-intent',
  collectionId: 'qa-private-group',
  expectedAmountRwf: 5000,
  receiverMomoNumber: '0788123456',
  receiverMomoNumberHash: 'synthetic-receiver-hash',
  receiverMomoLabel: 'Synthetic receiver',
  momoNetwork: 'mtn_momo',
  senderPhoneHash: 'synthetic-sender-hash',
  status: 'pending',
  createdAt: DateTime.utc(2026),
  expiresAt: DateTime.utc(2030),
);

void main() {
  late CollectCloudflareClient client;
  late _FlowRepository repository;
  var launches = 0;
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() async {
    launches = 0;
    SharedPreferences.setMockInitialValues({});
    client = CollectCloudflareClient(
      'http://127.0.0.1:1',
      httpClient: MockClient((_) async => authority.jsonResponse({})),
    );
    await client.auth.recoverSession(
      authority.session(authority.actor, authority.firstSession),
    );
    repository = _FlowRepository(client);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('collect/momo_ussd'), (
          call,
        ) async {
          launches++;
          return true;
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('collect/momo_ussd'),
          null,
        );
    await client.dispose();
  });
  Future<void> pump(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [collectRepositoryProvider.overrideWith((_) => repository)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: CollectTheme.light(),
          home: const ContributionFlowScreen(collectionId: 'qa-private-group'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '5000');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Continue to MoMo'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Continue to MoMo'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
  }

  Future<void> replaceSession(WidgetTester tester) async {
    final loaded = Completer<void>();
    repository.nextLoad = loaded;
    final previousGeneration = repository.sessionGeneration;
    await tester.runAsync(() async {
      await client.auth.recoverSession(
        authority.session(authority.actor, authority.nextSession),
      );
    });
    await tester.pumpAndSettle();
    expect(loaded.isCompleted, isTrue);
    expect(repository.sessionGeneration, greaterThan(previousGeneration));
    expect(repository.state.currentProfile!.id, authority.actor);
  }

  testWidgets(
    'replacement same-user session clears completed prepared payment',
    (tester) async {
      await pump(tester);
      expect(find.text('Open MoMo USSD'), findsOneWidget);
      await replaceSession(tester);
      expect(find.text('Open MoMo USSD'), findsNothing);
      expect(find.text('Continue to MoMo'), findsOneWidget);
      expect(repository.creates, 1);
      expect(launches, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'old preparation reply cannot rebuild a payment after replacement session',
    (tester) async {
      final reply = Completer<PaymentIntentModel>();
      repository.respond = (_) => reply.future;
      await pump(tester);
      await replaceSession(tester);
      reply.complete(_intent());
      await tester.pumpAndSettle();
      expect(find.text('Open MoMo USSD'), findsNothing);
      expect(launches, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'old preflight reply cannot launch USSD after replacement session',
    (tester) async {
      final reply = Completer<PaymentIntentModel>();
      repository.respond = (call) =>
          call == 1 ? Future.value(_intent()) : reply.future;
      await pump(tester);
      await tester.tap(find.text('Open MoMo USSD'));
      await tester.pumpAndSettle();
      expect(repository.creates, 2);
      await replaceSession(tester);
      reply.complete(_intent());
      await tester.pumpAndSettle();
      expect(launches, 0);
      expect(find.text('Open MoMo USSD'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('current captured session completes existing payment workflow', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Open MoMo USSD'));
    await tester.pumpAndSettle();
    expect(repository.creates, 2);
    expect(launches, 1);
    expect(tester.takeException(), isNull);
  });
}
