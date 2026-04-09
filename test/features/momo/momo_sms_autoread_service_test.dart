import 'dart:io';

import 'package:another_telephony/telephony.dart';
import 'package:cool_app/core/services/app_access_service.dart';
import 'package:cool_app/features/momo/repositories/momo_sms_ingestion_repository.dart';
import 'package:cool_app/features/momo/services/momo_sms_autoread_service.dart';
import 'package:cool_app/features/momo/services/momo_sms_sync_support.dart';
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
        locationService: FakeSmsAutoreadLocationService(),
        deviceSettingsService: FakeSmsAutoreadDeviceSettingsService(),
        nfcHceService: FakeSmsAutoreadNfcHceService(),
      );
      final service = MomoSmsAutoreadService(
        client: client,
        appAccessService: appAccessService,
      );

      await service.refresh();
      service.dispose();
    });

    test('syncInbox throws when SMS is not enabled in app', () async {
      final appAccessService = AppAccessService(
        openBox: Hive.openBox<bool>,
        locationService: FakeSmsAutoreadLocationService(),
        deviceSettingsService: FakeSmsAutoreadDeviceSettingsService(),
        nfcHceService: FakeSmsAutoreadNfcHceService(),
      );
      final service = MomoSmsAutoreadService(
        client: client,
        appAccessService: appAccessService,
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
        locationService: FakeSmsAutoreadLocationService(),
        deviceSettingsService: FakeSmsAutoreadDeviceSettingsService(),
        nfcHceService: FakeSmsAutoreadNfcHceService(),
      );
      final service = MomoSmsAutoreadService(
        client: client,
        appAccessService: appAccessService,
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
    late FakeSmsAutoreadOperationalHealthService operationalHealthService;

    setUp(() {
      mockClient = MockSmsAutoreadSupabaseClient();
      mockAuth = MockSmsAutoreadGoTrueClient();
      appAccessService = FakeAppAccessService();
      syncStateStore = MomoSmsSyncStateStore(openBox: Hive.openBox<String>);
      recordedSyncRuns = <Map<String, dynamic>>[];
      crashlytics = FakeSmsAutoreadCrashlyticsService();
      operationalHealthService = FakeSmsAutoreadOperationalHealthService();

      when(() => mockClient.auth).thenReturn(mockAuth);
    });

    test(
      'initial sync records a successful backfill and persists newest message',
      () async {
        final session = smsAutoreadSessionFor('user-initial');
        when(() => mockAuth.currentSession).thenReturn(session);

        DateTime? loadedCutoff;
        final ingestedCaptures = <MomoSmsCapture>[];
        final repository = FakeSmsAutoreadIngestionRepository(
          onIngest: (capture) async {
            ingestedCaptures.add(capture);
            return const MomoSmsIngestionResult(
              rawSmsId: 'raw-1',
              inserted: true,
              parseQueued: true,
            );
          },
        );
        final service = MomoSmsAutoreadService(
          client: mockClient,
          appAccessService: appAccessService,
          ingestionRepository: repository,
          syncStateStore: syncStateStore,
          syncRunAuditWriter: MomoSmsSyncRunAuditWriter(
            insert: (row) async =>
                recordedSyncRuns.add(Map<String, dynamic>.from(row)),
            crashlytics: crashlytics,
          ),
          operationalHealthService: operationalHealthService,
          supportsSmsAutoread: () => true,
          smsPermissionStatus: () async => PermissionStatus.granted,
          requestSmsPermission: () async => PermissionStatus.granted,
          inboxLoader: (cutoff) async {
            loadedCutoff = cutoff;
            return <SmsMessage>[
              smsAutoreadMessage(
                sender: 'M-Money',
                body: 'TxId: 100001. Payment of 1,500 RWF completed.',
                receivedAt: DateTime.utc(2026, 3, 22, 9, 30),
              ),
            ];
          },
        );

        final result = await service.syncInbox(
          trigger: MomoInboxSyncTrigger.initialPermissionGrant,
        );

        expect(result.incremental, isFalse);
        expect(result.scannedMessages, 1);
        expect(result.uploadedMessages, 1);
        expect(result.duplicateMessages, 0);
        expect(ingestedCaptures, hasLength(1));

        final syncRun = recordedSyncRuns.single;
        final scanStartedAt = DateTime.parse(
          syncRun['scan_started_at'] as String,
        ).toUtc();
        expect(loadedCutoff, scanStartedAt.subtract(const Duration(days: 365)));
        expect(syncRun['status'], 'succeeded');
        expect(syncRun['trigger'], 'initial_permission_grant');
        expect(syncRun['incremental'], isFalse);
        expect(syncRun['lookback_days'], 365);

        final syncState = await syncStateStore.read(session.user.id);
        expect(syncState.hasInitialBackfill, isTrue);
        expect(syncState.initialBackfillCompletedAt, isNotNull);
        expect(syncState.latestKnownMessageAt, result.newestMessageAt);
        expect(syncState.lastSuccessfulSyncAt, isNotNull);
      },
    );

    test(
      'manual sync uses overlap cutoff, preserves backfill marker, and records duplicates',
      () async {
        final session = smsAutoreadSessionFor('user-manual');
        when(() => mockAuth.currentSession).thenReturn(session);

        const priorBackfillAt = '2026-03-21T10:00:00.000Z';
        final latestKnownMessageAt = DateTime.utc(2026, 3, 22, 6, 0);
        await syncStateStore.write(
          session.user.id,
          MomoSmsSyncState(
            initialBackfillCompletedAt: DateTime.parse(priorBackfillAt).toUtc(),
            lastSuccessfulSyncAt: DateTime.utc(2026, 3, 22, 6, 15),
            latestKnownMessageAt: latestKnownMessageAt,
          ),
        );

        DateTime? loadedCutoff;
        final ingestedCaptures = <MomoSmsCapture>[];
        final repository = FakeSmsAutoreadIngestionRepository(
          onIngest: (capture) async {
            ingestedCaptures.add(capture);
            final inserted = !capture.body.contains('duplicate');
            return MomoSmsIngestionResult(
              rawSmsId: inserted ? 'raw-new' : 'raw-duplicate',
              inserted: inserted,
              parseQueued: inserted,
            );
          },
        );
        final service = MomoSmsAutoreadService(
          client: mockClient,
          appAccessService: appAccessService,
          ingestionRepository: repository,
          syncStateStore: syncStateStore,
          syncRunAuditWriter: MomoSmsSyncRunAuditWriter(
            insert: (row) async =>
                recordedSyncRuns.add(Map<String, dynamic>.from(row)),
            crashlytics: crashlytics,
          ),
          operationalHealthService: operationalHealthService,
          supportsSmsAutoread: () => true,
          smsPermissionStatus: () async => PermissionStatus.granted,
          requestSmsPermission: () async => PermissionStatus.granted,
          inboxLoader: (cutoff) async {
            loadedCutoff = cutoff;
            return <SmsMessage>[
              smsAutoreadMessage(
                sender: 'M-Money',
                body: 'TxId: 200001. Payment of 2,500 RWF completed.',
                receivedAt: DateTime.utc(2026, 3, 22, 9, 45),
              ),
              smsAutoreadMessage(
                sender: 'M-Money Alerts',
                body: 'TxId: 200002. duplicate payment of 2,500 RWF completed.',
                receivedAt: DateTime.utc(2026, 3, 22, 8, 45),
              ),
              smsAutoreadMessage(
                sender: 'M-Money',
                body: 'TxId: 199999. Older payment of 800 RWF completed.',
                receivedAt: DateTime.utc(2026, 3, 21, 16, 30),
              ),
            ];
          },
        );

        final result = await service.syncInbox(
          trigger: MomoInboxSyncTrigger.manual,
        );

        final expectedCutoff = latestKnownMessageAt.subtract(
          MomoSmsSyncPlanner.overlapWindow,
        );
        expect(loadedCutoff, expectedCutoff);
        expect(result.incremental, isTrue);
        expect(result.scannedMessages, 2);
        expect(result.uploadedMessages, 1);
        expect(result.duplicateMessages, 1);
        expect(ingestedCaptures, hasLength(2));
        for (final capture in ingestedCaptures) {
          expect(
            capture.receivedAt.isBefore(expectedCutoff),
            isFalse,
            reason:
                'capture ${capture.deviceMessageKey} fell before manual cutoff',
          );
        }

        final syncRun = recordedSyncRuns.single;
        final scanStartedAt = DateTime.parse(
          syncRun['scan_started_at'] as String,
        ).toUtc();
        expect(syncRun['status'], 'succeeded');
        expect(syncRun['trigger'], 'manual');
        expect(syncRun['incremental'], isTrue);
        expect(
          syncRun['lookback_days'],
          MomoSmsSyncPlanner.lookbackDaysFor(
            cutoff: expectedCutoff,
            now: scanStartedAt,
          ),
        );
        expect(syncRun['scanned_messages'], 2);
        expect(syncRun['uploaded_messages'], 1);
        expect(syncRun['duplicate_messages'], 1);

        final syncState = await syncStateStore.read(session.user.id);
        expect(
          syncState.initialBackfillCompletedAt?.toIso8601String(),
          priorBackfillAt,
        );
        expect(
          syncState.latestKnownMessageAt,
          DateTime.utc(2026, 3, 22, 9, 45),
        );
        expect(syncState.lastSuccessfulSyncAt, isNotNull);
      },
    );

    test(
      'sync failure records failed audit context and crashlytics reason',
      () async {
        final session = smsAutoreadSessionFor('user-failure');
        when(() => mockAuth.currentSession).thenReturn(session);

        final latestKnownMessageAt = DateTime.utc(2026, 3, 22, 6, 0);
        await syncStateStore.write(
          session.user.id,
          MomoSmsSyncState(
            initialBackfillCompletedAt: DateTime.utc(2026, 3, 21, 10, 0),
            lastSuccessfulSyncAt: DateTime.utc(2026, 3, 22, 6, 15),
            latestKnownMessageAt: latestKnownMessageAt,
          ),
        );

        final service = MomoSmsAutoreadService(
          client: mockClient,
          appAccessService: appAccessService,
          ingestionRepository: FakeSmsAutoreadIngestionRepository(
            onIngest: (_) async => throw UnimplementedError(),
          ),
          crashlytics: crashlytics,
          syncStateStore: syncStateStore,
          syncRunAuditWriter: MomoSmsSyncRunAuditWriter(
            insert: (row) async =>
                recordedSyncRuns.add(Map<String, dynamic>.from(row)),
            crashlytics: crashlytics,
          ),
          operationalHealthService: operationalHealthService,
          supportsSmsAutoread: () => true,
          smsPermissionStatus: () async => PermissionStatus.granted,
          requestSmsPermission: () async => PermissionStatus.granted,
          inboxLoader: (_) async => throw StateError('telephony down'),
        );

        await expectLater(
          service.syncInbox(trigger: MomoInboxSyncTrigger.manual),
          throwsA(isA<StateError>()),
        );

        final syncRun = recordedSyncRuns.single;
        final scanStartedAt = DateTime.parse(
          syncRun['scan_started_at'] as String,
        ).toUtc();
        final expectedCutoff = latestKnownMessageAt.subtract(
          MomoSmsSyncPlanner.overlapWindow,
        );
        expect(syncRun['status'], 'failed');
        expect(syncRun['trigger'], 'manual');
        expect(syncRun['incremental'], isTrue);
        expect(
          syncRun['lookback_days'],
          MomoSmsSyncPlanner.lookbackDaysFor(
            cutoff: expectedCutoff,
            now: scanStartedAt,
          ),
        );
        expect(syncRun['error_message'], contains('telephony down'));
        expect(
          syncRun['latest_known_message_at'],
          latestKnownMessageAt.toIso8601String(),
        );
        expect(
          crashlytics.recordedReasons,
          contains('momo_sms_inbox_sync_failed'),
        );
      },
    );
  });
}
