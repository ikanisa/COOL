import 'dart:io';

import 'package:cool_app/core/services/app_access_service.dart';
import 'package:cool_app/features/momo/services/momo_sms_autoread_service.dart';
import 'package:cool_app/features/momo/services/momo_sms_native_bridge.dart';
import 'package:cool_app/features/momo/services/momo_sms_sync_support.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FlutterAuthClientOptions, SupabaseClient;

import '../../helpers/fake_app_access_service.dart';
import 'momo_sms_autoread_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDir;
  late SupabaseClient client;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('cool_sms_autoread');
    Hive.init(hiveDir.path);
  });

  setUp(() {
    client = SupabaseClient(
      'http://127.0.0.1:54321',
      'test-anon-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });

  tearDown(() async {
    if (Hive.isBoxOpen(AppAccessService.boxName)) {
      await Hive.box<bool>(AppAccessService.boxName).clear();
      await Hive.box<bool>(AppAccessService.boxName).close();
    }
    await Hive.deleteBoxFromDisk(AppAccessService.boxName);

    for (final boxName in <String>[
      'momo_sms_sync_state',
      'momo_sms_retry_queue',
    ]) {
      if (Hive.isBoxOpen(boxName)) {
        await Hive.box<String>(boxName).clear();
        await Hive.box<String>(boxName).close();
      }
      await Hive.deleteBoxFromDisk(boxName);
    }
  });

  tearDownAll(() async {
    await hiveDir.delete(recursive: true);
  });

  group('MomoSmsAutoreadService gate chain', () {
    test('refresh stops when platform is not Android (web)', () async {
      final appAccessService = AppAccessService(
        openBox: Hive.openBox<bool>,
        deviceSettingsService: FakeSmsAutoreadDeviceSettingsService(),
        nfcHceService: FakeSmsAutoreadNfcHceService(),
      );
      final nativeBridgeChannel = _FakeNativeBridgeChannel();
      final service = MomoSmsAutoreadService(
        client: client,
        appAccessService: appAccessService,
        nativeBridge: MomoSmsNativeBridge(channel: nativeBridgeChannel.channel),
      );

      await service.refresh();
      service.dispose();
    });

    test('syncInbox throws when SMS is not enabled in app', () async {
      final appAccessService = AppAccessService(
        openBox: Hive.openBox<bool>,
        deviceSettingsService: FakeSmsAutoreadDeviceSettingsService(),
        nfcHceService: FakeSmsAutoreadNfcHceService(),
      );
      final nativeBridgeChannel = _FakeNativeBridgeChannel();
      final service = MomoSmsAutoreadService(
        client: client,
        appAccessService: appAccessService,
        nativeBridge: MomoSmsNativeBridge(channel: nativeBridgeChannel.channel),
      );

      if (Platform.isAndroid) {
        expect(
          () => service.syncInbox(trigger: MomoInboxSyncTrigger.manual),
          throwsA(isA<MomoSmsSyncException>()),
        );
      } else {
        expect(
          () => service.syncInbox(trigger: MomoInboxSyncTrigger.manual),
          throwsA(
            isA<MomoSmsSyncException>().having(
              (e) => e.message,
              'message',
              contains('Android'),
            ),
          ),
        );
      }

      service.dispose();
    });

    test('stop is safe to call multiple times', () async {
      final appAccessService = AppAccessService(
        openBox: Hive.openBox<bool>,
        deviceSettingsService: FakeSmsAutoreadDeviceSettingsService(),
        nfcHceService: FakeSmsAutoreadNfcHceService(),
      );
      final nativeBridgeChannel = _FakeNativeBridgeChannel();
      final service = MomoSmsAutoreadService(
        client: client,
        appAccessService: appAccessService,
        nativeBridge: MomoSmsNativeBridge(channel: nativeBridgeChannel.channel),
      );

      await service.stop();
      await service.stop();
      await service.stop(resetPermissionPromptState: true);

      service.dispose();
    });
  });

  group('MomoSmsAutoreadService sync contracts', () {
    late MockSmsAutoreadSupabaseClient mockClient;
    late MockSmsAutoreadGoTrueClient mockAuth;
    late FakeAppAccessService appAccessService;
    late MomoSmsSyncStateStore syncStateStore;
    late List<Map<String, dynamic>> recordedSyncRuns;
    late FakeSmsAutoreadCrashlyticsService crashlytics;
    late _FakeNativeBridgeChannel nativeBridgeChannel;

    setUp(() {
      mockClient = MockSmsAutoreadSupabaseClient();
      mockAuth = MockSmsAutoreadGoTrueClient();
      appAccessService = FakeAppAccessService();
      syncStateStore = MomoSmsSyncStateStore(openBox: Hive.openBox<String>);
      recordedSyncRuns = <Map<String, dynamic>>[];
      crashlytics = FakeSmsAutoreadCrashlyticsService();
      nativeBridgeChannel = _FakeNativeBridgeChannel();

      when(() => mockClient.auth).thenReturn(mockAuth);
    });

    test('initial sync via native bridge returns expected results', () async {
      final session = smsAutoreadSessionFor('user-initial');
      when(() => mockAuth.currentSession).thenReturn(session);

      nativeBridgeChannel.syncInboxResult = <String, dynamic>{
        'scannedMessages': 1,
        'uploadedMessages': 1,
        'duplicateMessages': 0,
        'queuedMessages': 1,
        'oldestMessageAt': '2026-03-22T09:30:00.000Z',
        'newestMessageAt': '2026-03-22T09:30:00.000Z',
        'rateLimited': false,
      };

      final nativeBridge = MomoSmsNativeBridge(
        channel: nativeBridgeChannel.channel,
      );
      final service = MomoSmsAutoreadService(
        client: mockClient,
        appAccessService: appAccessService,
        nativeBridge: nativeBridge,
        syncStateStore: syncStateStore,
        syncRunAuditWriter: MomoSmsSyncRunAuditWriter(
          insert: (row) async =>
              recordedSyncRuns.add(Map<String, dynamic>.from(row)),
          crashlytics: crashlytics,
        ),
        supportsSmsAutoread: () => true,
        smsPermissionStatus: () async => PermissionStatus.granted,
        requestSmsPermission: () async => PermissionStatus.granted,
        approvedSenderLoader: () async => const <String>['MMONEY'],
      );

      final result = await service.syncInbox(
        trigger: MomoInboxSyncTrigger.initialPermissionGrant,
      );

      expect(result.scannedMessages, 1);
      expect(result.uploadedMessages, 1);
      expect(result.duplicateMessages, 0);

      final syncState = await syncStateStore.read(session.user.id);
      expect(syncState.hasInitialBackfill, isTrue);
    });

    test(
      'manual sync preserves backfill marker and records duplicates',
      () async {
        final session = smsAutoreadSessionFor('user-manual');
        when(() => mockAuth.currentSession).thenReturn(session);

        const priorBackfillAt = '2026-03-21T10:00:00.000Z';
        await syncStateStore.write(
          session.user.id,
          MomoSmsSyncState(
            initialBackfillCompletedAt: DateTime.parse(priorBackfillAt).toUtc(),
            lastSuccessfulSyncAt: DateTime.utc(2026, 3, 22, 6, 15),
            latestKnownMessageAt: DateTime.utc(2026, 3, 22, 6, 0),
          ),
        );

        nativeBridgeChannel.syncInboxResult = <String, dynamic>{
          'scannedMessages': 3,
          'uploadedMessages': 1,
          'duplicateMessages': 2,
          'queuedMessages': 1,
          'oldestMessageAt': '2026-03-21T16:30:00.000Z',
          'newestMessageAt': '2026-03-22T09:45:00.000Z',
          'rateLimited': false,
        };

        final nativeBridge = MomoSmsNativeBridge(
          channel: nativeBridgeChannel.channel,
        );
        final service = MomoSmsAutoreadService(
          client: mockClient,
          appAccessService: appAccessService,
          nativeBridge: nativeBridge,
          syncStateStore: syncStateStore,
          syncRunAuditWriter: MomoSmsSyncRunAuditWriter(
            insert: (row) async =>
                recordedSyncRuns.add(Map<String, dynamic>.from(row)),
            crashlytics: crashlytics,
          ),
          supportsSmsAutoread: () => true,
          smsPermissionStatus: () async => PermissionStatus.granted,
          requestSmsPermission: () async => PermissionStatus.granted,
          approvedSenderLoader: () async => const <String>['MMONEY'],
        );

        final result = await service.syncInbox(
          trigger: MomoInboxSyncTrigger.manual,
        );

        expect(result.incremental, isTrue);
        expect(result.uploadedMessages, 1);
        expect(result.duplicateMessages, 2);

        final syncState = await syncStateStore.read(session.user.id);
        expect(
          syncState.initialBackfillCompletedAt?.toIso8601String(),
          priorBackfillAt,
        );
      },
    );

    test(
      'sync failure records failed audit context and crashlytics reason',
      () async {
        final session = smsAutoreadSessionFor('user-failure');
        when(() => mockAuth.currentSession).thenReturn(session);

        await syncStateStore.write(
          session.user.id,
          MomoSmsSyncState(
            initialBackfillCompletedAt: DateTime.utc(2026, 3, 21, 10, 0),
            lastSuccessfulSyncAt: DateTime.utc(2026, 3, 22, 6, 15),
            latestKnownMessageAt: DateTime.utc(2026, 3, 22, 6, 0),
          ),
        );

        nativeBridgeChannel.syncInboxError = PlatformException(
          code: 'SYNC_ERROR',
          message: 'telephony down',
        );

        final nativeBridge = MomoSmsNativeBridge(
          channel: nativeBridgeChannel.channel,
        );
        final service = MomoSmsAutoreadService(
          client: mockClient,
          appAccessService: appAccessService,
          nativeBridge: nativeBridge,
          crashlytics: crashlytics,
          syncStateStore: syncStateStore,
          syncRunAuditWriter: MomoSmsSyncRunAuditWriter(
            insert: (row) async =>
                recordedSyncRuns.add(Map<String, dynamic>.from(row)),
            crashlytics: crashlytics,
          ),
          supportsSmsAutoread: () => true,
          smsPermissionStatus: () async => PermissionStatus.granted,
          requestSmsPermission: () async => PermissionStatus.granted,
          approvedSenderLoader: () async => const <String>['MMONEY'],
        );

        await expectLater(
          service.syncInbox(trigger: MomoInboxSyncTrigger.manual),
          throwsA(isA<PlatformException>()),
        );

        expect(
          crashlytics.recordedReasons,
          contains('momo_sms_native_inbox_sync_failed'),
        );
      },
    );
  });
}

/// Fake method channel handler that simulates native bridge responses.
class _FakeNativeBridgeChannel {
  _FakeNativeBridgeChannel() {
    channel = const MethodChannel('app.cool.mobile/momo_sms_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, _handler);
  }

  late final MethodChannel channel;

  Map<String, dynamic>? syncInboxResult;
  PlatformException? syncInboxError;

  final List<Map<String, dynamic>> configures = <Map<String, dynamic>>[];

  Future<dynamic> _handler(MethodCall call) async {
    switch (call.method) {
      case 'configurePipeline':
        configures.add(Map<String, dynamic>.from(call.arguments as Map));
        return null;
      case 'clearPipelineSession':
        return null;
      case 'getQueueStatus':
        return <String, dynamic>{
          'pendingCount': 0,
          'failedCount': 0,
          'syncedCount': 0,
          'totalCount': 0,
        };
      case 'syncPendingNow':
        return <String, dynamic>{
          'uploadedMessages': 0,
          'duplicateMessages': 0,
          'failedMessages': 0,
          'rateLimited': false,
        };
      case 'syncInbox':
        if (syncInboxError != null) {
          throw syncInboxError!;
        }
        return syncInboxResult ??
            <String, dynamic>{
              'scannedMessages': 0,
              'uploadedMessages': 0,
              'duplicateMessages': 0,
              'queuedMessages': 0,
              'rateLimited': false,
            };
      default:
        return null;
    }
  }
}
