import 'dart:io';

import 'package:another_telephony/telephony.dart';
import 'package:cool_app/core/services/app_access_service.dart';
import 'package:cool_app/core/services/crashlytics_service.dart';
import 'package:cool_app/core/services/device_settings_service.dart';
import 'package:cool_app/core/services/location_service.dart';
import 'package:cool_app/core/services/operational_health_service.dart';
import 'package:cool_app/features/momo/repositories/momo_sms_ingestion_repository.dart';
import 'package:cool_app/features/momo/services/momo_sms_autoread_service.dart';
import 'package:cool_app/features/momo/services/momo_sms_sync_support.dart';
import 'package:cool_app/features/momo/services/nfc_hce_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FlutterAuthClientOptions, GoTrueClient, Session, SupabaseClient, User;

import '../../helpers/fake_app_access_service.dart';

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

    for (final boxName in <String>['momo_sms_sync_state', 'momo_sms_retry_queue']) {
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
        locationService: _FakeLocationService(),
        deviceSettingsService: _FakeDeviceSettingsService(),
        nfcHceService: _FakeNfcHceService(),
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
        locationService: _FakeLocationService(),
        deviceSettingsService: _FakeDeviceSettingsService(),
        nfcHceService: _FakeNfcHceService(),
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
        locationService: _FakeLocationService(),
        deviceSettingsService: _FakeDeviceSettingsService(),
        nfcHceService: _FakeNfcHceService(),
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
    late _MockSupabaseClient mockClient;
    late _MockGoTrueClient mockAuth;
    late FakeAppAccessService appAccessService;
    late MomoSmsSyncStateStore syncStateStore;
    late List<Map<String, dynamic>> recordedSyncRuns;
    late _FakeCrashlyticsService crashlytics;
    late _FakeOperationalHealthService operationalHealthService;

    setUp(() {
      mockClient = _MockSupabaseClient();
      mockAuth = _MockGoTrueClient();
      appAccessService = FakeAppAccessService();
      syncStateStore = MomoSmsSyncStateStore(openBox: Hive.openBox<String>);
      recordedSyncRuns = <Map<String, dynamic>>[];
      crashlytics = _FakeCrashlyticsService();
      operationalHealthService = _FakeOperationalHealthService();

      when(() => mockClient.auth).thenReturn(mockAuth);
    });

    test(
      'initial sync records a successful backfill and persists newest message',
      () async {
        final session = _sessionFor('user-initial');
        when(() => mockAuth.currentSession).thenReturn(session);

        DateTime? loadedCutoff;
        final ingestedCaptures = <MomoSmsCapture>[];
        final repository = _FakeIngestionRepository(
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
            insert: (row) async => recordedSyncRuns.add(
              Map<String, dynamic>.from(row),
            ),
            crashlytics: crashlytics,
          ),
          operationalHealthService: operationalHealthService,
          supportsSmsAutoread: () => true,
          smsPermissionStatus: () async => PermissionStatus.granted,
          requestSmsPermission: () async => PermissionStatus.granted,
          inboxLoader: (cutoff) async {
            loadedCutoff = cutoff;
            return <SmsMessage>[
              _smsMessage(
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
        expect(
          loadedCutoff,
          scanStartedAt.subtract(const Duration(days: 365)),
        );
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
        final session = _sessionFor('user-manual');
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
        final repository = _FakeIngestionRepository(
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
            insert: (row) async => recordedSyncRuns.add(
              Map<String, dynamic>.from(row),
            ),
            crashlytics: crashlytics,
          ),
          operationalHealthService: operationalHealthService,
          supportsSmsAutoread: () => true,
          smsPermissionStatus: () async => PermissionStatus.granted,
          requestSmsPermission: () async => PermissionStatus.granted,
          inboxLoader: (cutoff) async {
            loadedCutoff = cutoff;
            return <SmsMessage>[
              _smsMessage(
                sender: 'M-Money',
                body: 'TxId: 200001. Payment of 2,500 RWF completed.',
                receivedAt: DateTime.utc(2026, 3, 22, 9, 45),
              ),
              _smsMessage(
                sender: 'M-Money Alerts',
                body: 'TxId: 200002. duplicate payment of 2,500 RWF completed.',
                receivedAt: DateTime.utc(2026, 3, 22, 8, 45),
              ),
              _smsMessage(
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
            reason: 'capture ${capture.deviceMessageKey} fell before manual cutoff',
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
        expect(syncState.latestKnownMessageAt, DateTime.utc(2026, 3, 22, 9, 45));
        expect(syncState.lastSuccessfulSyncAt, isNotNull);
      },
    );

    test('sync failure records failed audit context and crashlytics reason', () async {
      final session = _sessionFor('user-failure');
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
        ingestionRepository: _FakeIngestionRepository(
          onIngest: (_) async => throw UnimplementedError(),
        ),
        crashlytics: crashlytics,
        syncStateStore: syncStateStore,
        syncRunAuditWriter: MomoSmsSyncRunAuditWriter(
          insert: (row) async => recordedSyncRuns.add(
            Map<String, dynamic>.from(row),
          ),
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
      expect(crashlytics.recordedReasons, contains('momo_sms_inbox_sync_failed'));
    });
  });

  group('MomoSmsIngestionRepository sender alignment', () {
    test('approvedInboxSenderIds covers all normalized tokens', () {
      final normalizedFromList = MomoSmsIngestionRepository
          .approvedInboxSenderIds
          .map((s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''))
          .toSet();

      const expectedTokens = <String>{
        'mmoney',
        'mmoneyalerts',
        'mobilemoney',
        'momo',
        'momoalerts',
        'mtnmomo',
        'mtnmomorwanda',
      };

      for (final token in expectedTokens) {
        expect(
          normalizedFromList.contains(token),
          isTrue,
          reason: 'Token "$token" is not covered by approvedInboxSenderIds',
        );
      }
    });

    test('accepts newly added sender variants', () {
      expect(
        MomoSmsIngestionRepository.isApprovedSender('M-Money Alerts'),
        isTrue,
      );
      expect(
        MomoSmsIngestionRepository.isApprovedSender('MoMo Alerts'),
        isTrue,
      );
      expect(
        MomoSmsIngestionRepository.isApprovedSender('MTN MoMo Rwanda'),
        isTrue,
      );
    });

    test('flags sender drift for unapproved transactional bodies', () {
      final metadata = MomoSmsIngestionRepository.senderDriftTelemetry(
        sender: 'MTN Rwanda',
        body:
            'TxId: 123456. Your payment of 1,200 RWF was completed. New balance: 8,900 RWF.',
      );

      expect(metadata, isNotNull);
      expect(metadata!['sender_token'], 'mtnrwanda');
      expect(metadata['sender_kind'], 'alias');
      expect(metadata['has_tx_reference'], isTrue);
      expect(metadata['contains_txid'], isTrue);
      expect(metadata['contains_rwf'], isTrue);
    });

    test('ignores approved senders and non-transactional bodies for drift', () {
      expect(
        MomoSmsIngestionRepository.senderDriftTelemetry(
          sender: 'M-Money',
          body: 'TxId: 123456. Payment of 500 RWF completed.',
        ),
        isNull,
      );
      expect(
        MomoSmsIngestionRepository.senderDriftTelemetry(
          sender: 'Unknown Sender',
          body: 'Welcome to your new plan.',
        ),
        isNull,
      );
      expect(
        MomoSmsIngestionRepository.senderDriftTelemetry(
          sender: 'BANK',
          body:
              'Your account was debited 5,000 RWF. Available balance 95,000 RWF.',
        ),
        isNull,
      );
    });
  });
}

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _FakeOperationalHealthService extends OperationalHealthService {
  _FakeOperationalHealthService()
    : super(client: _MockSupabaseClient());

  final List<Map<String, dynamic>> recordedEvents = <Map<String, dynamic>>[];

  @override
  Future<void> recordEvent({
    required String service,
    required String component,
    required String message,
    OperationalHealthStatus status = OperationalHealthStatus.ok,
    OperationalHealthSeverity? severity,
    String? issueCode,
    String? functionName,
    String? userId,
    String? subjectType,
    String? subjectId,
    Map<String, dynamic> metadata = const <String, dynamic>{},
    DateTime? occurredAt,
  }) async {
    recordedEvents.add(<String, dynamic>{
      'service': service,
      'component': component,
      'message': message,
      'status': status.name,
      'severity': (severity ?? OperationalHealthSeverity.info).name,
      'issue_code': issueCode,
      'user_id': userId,
      'subject_type': subjectType,
      'subject_id': subjectId,
      'metadata': Map<String, dynamic>.from(metadata),
    });
  }
}

class _FakeIngestionRepository extends MomoSmsIngestionRepository {
  _FakeIngestionRepository({
    required this.onIngest,
  }) : super(client: _MockSupabaseClient());

  final Future<MomoSmsIngestionResult?> Function(MomoSmsCapture capture) onIngest;

  @override
  Future<MomoSmsIngestionResult?> ingestCapture({
    required MomoSmsCapture capture,
    String? userId,
  }) {
    return onIngest(capture);
  }
}

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

SmsMessage _smsMessage({
  required String sender,
  required String body,
  required DateTime receivedAt,
}) {
  return SmsMessage.fromMap(<String, String>{
    'address': sender,
    'body': body,
    'date': receivedAt.millisecondsSinceEpoch.toString(),
  }, const <SmsColumn>[
    SmsColumn.ADDRESS,
    SmsColumn.BODY,
    SmsColumn.DATE,
  ]);
}

class _FakeDeviceSettingsService extends DeviceSettingsService {
  @override
  Future<bool> openNfcSettings() async => true;
}

class _FakeNfcHceService extends NfcHceService {
  @override
  Future<bool> isSupported() async => false;

  @override
  Future<bool> isPaymentRequestActive() async => false;

  @override
  Future<void> stopPaymentRequest() async {}
}

class _FakeLocationService implements LocationService {
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.denied;

  @override
  double calculateDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) => 0;

  @override
  Future<Position> getCurrentLocation({
    LocationAccuracy accuracy = LocationAccuracy.high,
    Duration? timeLimit,
  }) async => throw UnimplementedError();

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() async =>
      LocationAccuracyStatus.precise;

  @override
  Future<Position?> getLastKnownLocation() async => null;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  bool isWithin10km(Position userPos, double targetLat, double targetLng) =>
      true;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.denied;

  @override
  Future<void> startLocationUpdates(ValueChanged<Position> onUpdate) async {}

  @override
  Future<void> stopLocationUpdates() async {}
}
