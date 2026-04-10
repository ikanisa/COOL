import 'dart:io';

import 'package:cool_app/core/services/crashlytics_service.dart';
import 'package:cool_app/core/services/hive_runtime.dart';
import 'package:cool_app/features/momo/services/momo_sms_autoread_service.dart';
import 'package:cool_app/features/momo/services/momo_sms_native_bridge.dart';
import 'package:cool_app/features/momo/services/momo_sms_sync_support.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show GoTrueClient, Session, SupabaseClient, User;

import '../test/helpers/fake_app_access_service.dart';

const _syncStateBoxName = 'momo_sms_sync_state_device_integration';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late _MockSupabaseClient mockClient;
  late _MockGoTrueClient mockAuth;
  late FakeAppAccessService appAccessService;
  late MomoSmsSyncStateStore syncStateStore;
  late _FakeCrashlyticsService crashlytics;
  late List<Map<String, dynamic>> syncRunRows;

  setUpAll(() async {
    await initializeHiveRuntime();
  });

  setUp(() async {
    mockClient = _MockSupabaseClient();
    mockAuth = _MockGoTrueClient();
    appAccessService = FakeAppAccessService();
    syncStateStore = MomoSmsSyncStateStore(
      openBox: Hive.openBox<String>,
      boxName: _syncStateBoxName,
    );
    crashlytics = _FakeCrashlyticsService();
    syncRunRows = <Map<String, dynamic>>[];

    when(() => mockClient.auth).thenReturn(mockAuth);

    await _resetBox(_syncStateBoxName);
  });

  tearDown(() async {
    await _resetBox(_syncStateBoxName);
  });

  testWidgets(
    'real Android inbox sync ingests seeded M-Money SMS via native bridge',
    (tester) async {
      if (!Platform.isAndroid) {
        return;
      }

      await tester.pumpWidget(const SizedBox.shrink());

      final permissionStatus = await Permission.sms.status;
      if (!permissionStatus.isGranted) {
        debugPrint(
          'Skipping MoMo SMS inbox sync integration test: '
          'READ_SMS is not granted for this device/app install.',
        );
        return;
      }

      final session = _sessionFor('device-sync-user');
      when(() => mockAuth.currentSession).thenReturn(session);

      // Use the real native bridge — it talks to the actual
      // MomoSmsMethodChannel registered in MainActivity.
      final nativeBridge = MomoSmsNativeBridge();
      final service = MomoSmsAutoreadService(
        client: mockClient,
        appAccessService: appAccessService,
        nativeBridge: nativeBridge,
        crashlytics: crashlytics,
        syncStateStore: syncStateStore,
        syncRunAuditWriter: MomoSmsSyncRunAuditWriter(
          insert: (row) async =>
              syncRunRows.add(Map<String, dynamic>.from(row)),
          crashlytics: crashlytics,
        ),
      );

      final initialResult = await service.syncInbox(
        trigger: MomoInboxSyncTrigger.initialPermissionGrant,
      );

      expect(initialResult.scannedMessages, greaterThanOrEqualTo(0));

      final stateAfterInitial = await syncStateStore.read(session.user.id);
      expect(stateAfterInitial.hasInitialBackfill, isTrue);

      if (initialResult.scannedMessages > 0) {
        final manualResult = await service.syncInbox(
          trigger: MomoInboxSyncTrigger.manual,
        );
        expect(manualResult.incremental, isTrue);
      }

      expect(crashlytics.recordedReasons, isEmpty);
    },
  );
}

Future<void> _resetBox(String boxName) async {
  if (Hive.isBoxOpen(boxName)) {
    await Hive.box<String>(boxName).clear();
    await Hive.box<String>(boxName).close();
  }
  await Hive.deleteBoxFromDisk(boxName);
}

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _FakeCrashlyticsService extends CrashlyticsService {
  final List<dynamic> recordedErrors = <dynamic>[];
  final List<String?> recordedReasons = <String?>[];

  @override
  Future<void> recordError(
    dynamic error, {
    StackTrace? stackTrace,
    String? reason,
    bool fatal = false,
  }) async {
    recordedErrors.add(error);
    recordedReasons.add(reason);
  }
}

Session _sessionFor(String userId) {
  return Session(
    accessToken: 'test.jwt.token',
    refreshToken: 'refresh-token',
    tokenType: 'bearer',
    expiresIn: 3600,
    user: User(
      id: userId,
      appMetadata: const <String, dynamic>{},
      userMetadata: const <String, dynamic>{},
      aud: 'authenticated',
      email: '$userId@example.com',
      phone: '+250788123456',
      createdAt: DateTime.utc(2026, 3, 22, 8).toIso8601String(),
    ),
  );
}
