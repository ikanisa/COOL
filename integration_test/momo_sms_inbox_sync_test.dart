import 'dart:io';

import 'package:cool_app/core/services/crashlytics_service.dart';
import 'package:cool_app/core/services/hive_runtime.dart';
import 'package:cool_app/core/services/operational_health_service.dart';
import 'package:cool_app/features/momo/repositories/momo_sms_ingestion_repository.dart';
import 'package:cool_app/features/momo/services/momo_sms_autoread_service.dart';
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
const _seedBodyPrefix = 'Cool CI M-Money Sync';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late _MockSupabaseClient mockClient;
  late _MockGoTrueClient mockAuth;
  late FakeAppAccessService appAccessService;
  late MomoSmsSyncStateStore syncStateStore;
  late _FakeCrashlyticsService crashlytics;
  late _FakeOperationalHealthService operationalHealthService;
  late List<Map<String, dynamic>> syncRunRows;
  late _FakeIngestionRepository ingestionRepository;

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
    operationalHealthService = _FakeOperationalHealthService();
    syncRunRows = <Map<String, dynamic>>[];
    ingestionRepository = _FakeIngestionRepository();

    when(() => mockClient.auth).thenReturn(mockAuth);

    await _resetBox(_syncStateBoxName);
  });

  tearDown(() async {
    await _resetBox(_syncStateBoxName);
  });

  testWidgets(
    'real Android inbox sync ingests seeded M-Money SMS and narrows manual overlap',
    (tester) async {
      if (!Platform.isAndroid) {
        return;
      }

      await tester.pumpWidget(const SizedBox.shrink());

      final permissionStatus = await Permission.sms.status;
      expect(
        permissionStatus.isGranted,
        isTrue,
        reason:
            'READ_SMS must be granted before running this device integration test.',
      );

      final session = _sessionFor('device-sync-user');
      when(() => mockAuth.currentSession).thenReturn(session);

      final service = MomoSmsAutoreadService(
        client: mockClient,
        appAccessService: appAccessService,
        ingestionRepository: ingestionRepository,
        crashlytics: crashlytics,
        operationalHealthService: operationalHealthService,
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

      expect(initialResult.incremental, isFalse);
      expect(initialResult.scannedMessages, 3);
      expect(initialResult.uploadedMessages, 3);
      expect(initialResult.duplicateMessages, 0);

      final stateAfterInitial = await syncStateStore.read(session.user.id);
      expect(stateAfterInitial.hasInitialBackfill, isTrue);
      expect(stateAfterInitial.latestKnownMessageAt, isNotNull);

      final manualStartCount = ingestionRepository.ingestedCaptures.length;
      final manualResult = await service.syncInbox(
        trigger: MomoInboxSyncTrigger.manual,
      );

      expect(manualResult.incremental, isTrue);
      expect(manualResult.scannedMessages, 2);
      expect(manualResult.uploadedMessages, 0);
      expect(manualResult.duplicateMessages, 2);

      final manualCaptures = ingestionRepository.ingestedCaptures
          .skip(manualStartCount)
          .toList();
      expect(manualCaptures, hasLength(2));
      expect(
        manualCaptures.every(
          (capture) => capture.body.startsWith(_seedBodyPrefix),
        ),
        isTrue,
      );

      expect(syncRunRows, hasLength(2));
      expect(syncRunRows.first['trigger'], 'initial_permission_grant');
      expect(syncRunRows.first['status'], 'succeeded');
      expect(syncRunRows.first['lookback_days'], 365);
      expect(syncRunRows.last['trigger'], 'manual');
      expect(syncRunRows.last['status'], 'succeeded');
      expect(syncRunRows.last['incremental'], isTrue);
      expect(syncRunRows.last['lookback_days'], 0);
      expect(syncRunRows.last['scanned_messages'], 2);
      expect(syncRunRows.last['uploaded_messages'], 0);
      expect(syncRunRows.last['duplicate_messages'], 2);
      expect(crashlytics.recordedReasons, isEmpty);

      final stateAfterManual = await syncStateStore.read(session.user.id);
      expect(
        stateAfterManual.initialBackfillCompletedAt,
        stateAfterInitial.initialBackfillCompletedAt,
      );
      expect(
        stateAfterManual.latestKnownMessageAt,
        stateAfterInitial.latestKnownMessageAt,
      );
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

class _FakeIngestionRepository extends MomoSmsIngestionRepository {
  _FakeIngestionRepository() : super(client: _MockSupabaseClient());

  final List<MomoSmsCapture> ingestedCaptures = <MomoSmsCapture>[];
  final Set<String> _seenKeys = <String>{};

  @override
  Future<MomoSmsIngestionResult?> ingestCapture({
    required MomoSmsCapture capture,
    String? userId,
  }) async {
    ingestedCaptures.add(capture);
    final inserted = _seenKeys.add(capture.deviceMessageKey);
    return MomoSmsIngestionResult(
      rawSmsId: capture.deviceMessageKey,
      inserted: inserted,
      parseQueued: inserted,
    );
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

class _FakeOperationalHealthService extends OperationalHealthService {
  _FakeOperationalHealthService() : super(client: _MockSupabaseClient());

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
  }) async {}
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
