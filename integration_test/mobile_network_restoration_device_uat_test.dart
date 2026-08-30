import 'dart:io';

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/collect_theme_controller.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/providers/collect_app_state.dart';
import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _probeHost = String.fromEnvironment(
  'COLLECT_NETWORK_UAT_HOST',
  defaultValue: '10.0.2.2',
);
const _probePort = int.fromEnvironment(
  'COLLECT_NETWORK_UAT_PORT',
  defaultValue: 54331,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'controlled emulator network loss restores stale cache and resyncs online',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      const cache = CollectOfflineCache(
        preferencesKey: 'collect.offline_snapshot.network_restoration_uat',
      );
      final online = _ControlledNetworkRepository(offlineCache: cache);
      await online.signInWithOtp(phone: '+250788123456', otp: '123456');
      final intent = await online.createPaymentIntent(
        const PaymentIntentDraft(collectionId: 'col-church', amountRwf: 21000),
      );
      final savedAt = DateTime.utc(2026, 7, 30, 12);
      await cache.save(_snapshotFrom(online.state, savedAt: savedAt));

      await _waitForProbe(
        reachable: true,
        timeout: const Duration(seconds: 45),
      );
      await _pumpCollectApp(
        tester,
        initialLocation: '/groups/col-church/contribute',
        repository: online,
      );
      expect(find.text('Review contribution'), findsWidgets);
      expect(online.intentById(intent.id).status, 'pending');
      _mark('ready-for-radio-loss');

      await _waitForProbe(
        reachable: false,
        timeout: const Duration(seconds: 120),
      );
      _mark('radio-loss-observed');

      final offline = CollectRepository(offlineCache: cache);
      final restored = await offline.restoreOfflineSnapshot(
        reason: 'SocketException: controlled emulator radio loss',
      );
      expect(restored, isTrue);
      final offlineContainer = await _pumpCollectApp(
        tester,
        initialLocation: '/groups/col-church/contribute',
        repository: offline,
      );

      expect(find.text('Review contribution'), findsWidgets);
      expect(find.text('St Michel building fund'), findsWidgets);
      expect(find.textContaining('Offline saved data'), findsWidgets);
      expect(offline.state.usingStaleCache, isTrue);
      expect(offline.state.lastSuccessfulSyncAt, savedAt);
      expect(offline.intentById(intent.id).status, 'pending');
      expect(offline.contributionsFor('col-church'), hasLength(2));
      expect(
        offline.state.contributions.any((item) => item.transactionId != null),
        isFalse,
      );

      expect(
        offlineContainer.read(connectivityStatusProvider),
        ConnectivityStatus.offlineStale,
      );
      expect(
        offlineContainer.read(realtimeSyncStatusProvider),
        RealtimeSyncStatus.needsAttention,
      );
      expect(
        offlineContainer.read(
          paymentUiStatusProvider(
            PaymentStatusKey(collectionId: 'col-church', intentId: intent.id),
          ),
        ),
        PaymentUiStatus.pending,
      );
      _mark('stale-cache-offline-ui-visible');
      _mark('ready-for-radio-restoration');

      await _waitForProbe(
        reachable: true,
        timeout: const Duration(seconds: 120),
      );
      final authoritative = _ControlledNetworkRepository();
      final restoredIntent = await authoritative.createPaymentIntent(
        const PaymentIntentDraft(collectionId: 'col-church', amountRwf: 31000),
      );
      final resyncAt = DateTime.utc(2026, 7, 30, 12, 5);
      authoritative.applyAuthoritativeSync(
        _snapshotFrom(authoritative.state, savedAt: resyncAt),
      );
      final onlineContainer = await _pumpCollectApp(
        tester,
        initialLocation: '/groups/col-church/contribute',
        repository: authoritative,
      );

      expect(find.text('Review contribution'), findsWidgets);
      expect(find.text('St Michel building fund'), findsWidgets);
      expect(find.textContaining('Offline saved data'), findsNothing);
      expect(authoritative.state.usingStaleCache, isFalse);
      expect(authoritative.state.lastError, isNull);
      expect(authoritative.state.lastSuccessfulSyncAt, resyncAt);
      expect(
        authoritative.collectionById('col-church').receiverDisplayLabel,
        'Restored treasury',
      );
      expect(authoritative.intentById(restoredIntent.id).status, 'pending');

      expect(
        onlineContainer.read(connectivityStatusProvider),
        ConnectivityStatus.online,
      );
      expect(
        onlineContainer.read(realtimeSyncStatusProvider),
        RealtimeSyncStatus.current,
      );
      expect(
        onlineContainer.read(offlineSnapshotStatusProvider).label,
        'Live data',
      );
      _mark('authoritative-online-resync-pass');
      await Future<void>.delayed(const Duration(seconds: 12));
      await _pumpFrames(tester);
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

Future<ProviderContainer> _pumpCollectApp(
  WidgetTester tester, {
  required String initialLocation,
  required CollectRepository repository,
}) async {
  final router = createAppRouter(initialLocation: initialLocation);
  final container = ProviderContainer(
    overrides: [
      appRouterProvider.overrideWithValue(router),
      collectRepositoryProvider.overrideWith((ref) => repository),
      collectThemeModeProvider.overrideWith(
        (ref) => CollectThemeModeController(
          initialMode: ThemeMode.dark,
          loadPersistedMode: false,
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const CollectApp()),
  );
  await _pumpFrames(tester);
  return container;
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var index = 0; index < 14; index += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _waitForProbe({
  required bool reachable,
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final observed = await _probeReachable();
    if (observed == reachable) return;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  fail(
    'Timed out waiting for $_probeHost:$_probePort reachable=$reachable '
    'in controlled emulator network UAT.',
  );
}

Future<bool> _probeReachable() async {
  try {
    final socket = await Socket.connect(
      _probeHost,
      _probePort,
      timeout: const Duration(seconds: 2),
    );
    socket.destroy();
    return true;
  } on Object {
    return false;
  }
}

void _mark(String marker) {
  // ignore: avoid_print
  print('collect_network_uat:$marker');
}

class _ControlledNetworkRepository extends CollectRepository {
  _ControlledNetworkRepository({super.offlineCache}) : super.fixture();

  void applyAuthoritativeSync(CollectOfflineSnapshot snapshot) {
    state = state.copyWith(
      currentProfile: snapshot.currentProfile,
      collections: snapshot.collections,
      paymentIntents: snapshot.paymentIntents,
      contributions: snapshot.contributions,
      isLoading: false,
      usingStaleCache: false,
      lastSuccessfulSyncAt: snapshot.savedAt,
    );
  }
}

CollectOfflineSnapshot _snapshotFrom(
  CollectState state, {
  required DateTime savedAt,
}) {
  return CollectOfflineSnapshot(
    savedAt: savedAt,
    currentProfile: state.currentProfile,
    collections: state.collections,
    paymentIntents: state.paymentIntents,
    contributions: state.contributions,
  );
}
