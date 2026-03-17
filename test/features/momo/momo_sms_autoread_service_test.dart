import 'dart:io';

import 'package:cool_app/core/services/app_access_service.dart';
import 'package:cool_app/core/services/device_settings_service.dart';
import 'package:cool_app/core/services/location_service.dart';
import 'package:cool_app/features/momo/repositories/momo_sms_ingestion_repository.dart';
import 'package:cool_app/features/momo/services/momo_sms_autoread_service.dart';
import 'package:cool_app/features/momo/services/nfc_hce_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FlutterAuthClientOptions, SupabaseClient;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDir;
  late SupabaseClient client;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('cool_sms_autoread');
    Hive.init(hiveDir.path);
    client = SupabaseClient(
      'http://127.0.0.1:54321',
      'test-anon-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });

  tearDown(() async {
    final boxName = AppAccessService.boxName;
    if (Hive.isBoxOpen(boxName)) {
      await Hive.box<bool>(boxName).clear();
      await Hive.box<bool>(boxName).close();
    }
    await Hive.deleteBoxFromDisk(boxName);
  });

  tearDownAll(() async {
    await hiveDir.delete(recursive: true);
  });

  group('MomoSmsAutoreadService gate chain', () {
    test('refresh stops when platform is not Android (web)', () async {
      // On non-Android test runner, the service should stop immediately.
      // This test verifies that refresh() doesn't throw and stays inactive.
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

      // Should complete without error even though we can't listen on
      // non-Android.
      await service.refresh();

      // Service should not be listening.
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

      // SMS defaults to off, so syncInbox should throw.
      if (Platform.isAndroid) {
        expect(
          () => service.syncInbox(
            trigger: MomoInboxSyncTrigger.manual,
          ),
          throwsA(isA<MomoSmsSyncException>()),
        );
      } else {
        // On non-Android, throws 'Android only'.
        expect(
          () => service.syncInbox(
            trigger: MomoInboxSyncTrigger.manual,
          ),
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

      // Calling stop multiple times should not throw.
      await service.stop();
      await service.stop();
      await service.stop(resetPermissionPromptState: true);

      service.dispose();
    });
  });

  group('MomoSmsIngestionRepository sender alignment', () {
    test('approvedInboxSenderIds covers all normalized tokens', () {
      // Every normalized token from _normalizedApprovedSenderTokens
      // should be reachable by normalizing at least one entry in
      // approvedInboxSenderIds.
      final normalizedFromList = MomoSmsIngestionRepository
          .approvedInboxSenderIds
          .map((s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''))
          .toSet();

      // These are the tokens the listener matches against.
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
  });
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
  double calculateDistance(double lat1, double lng1, double lat2, double lng2) =>
      0;

  @override
  Future<Position> getCurrentLocation({
    LocationAccuracy accuracy = LocationAccuracy.high,
    Duration? timeLimit,
  }) async =>
      throw UnimplementedError();

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
