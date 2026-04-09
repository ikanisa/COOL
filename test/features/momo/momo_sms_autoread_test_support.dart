import 'package:another_telephony/telephony.dart';
import 'package:cool_app/core/services/crashlytics_service.dart';
import 'package:cool_app/core/services/device_settings_service.dart';
import 'package:cool_app/core/services/location_service.dart';
import 'package:cool_app/core/services/operational_health_service.dart';
import 'package:cool_app/features/momo/repositories/momo_sms_ingestion_repository.dart';
import 'package:cool_app/features/momo/services/nfc_hce_service.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show GoTrueClient, Session, SupabaseClient, User;

class MockSmsAutoreadSupabaseClient extends Mock implements SupabaseClient {}

class MockSmsAutoreadGoTrueClient extends Mock implements GoTrueClient {}

class FakeSmsAutoreadOperationalHealthService extends OperationalHealthService {
  FakeSmsAutoreadOperationalHealthService()
    : super(client: MockSmsAutoreadSupabaseClient());

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

class FakeSmsAutoreadIngestionRepository extends MomoSmsIngestionRepository {
  FakeSmsAutoreadIngestionRepository({required this.onIngest})
    : super(client: MockSmsAutoreadSupabaseClient());

  final Future<MomoSmsIngestionResult?> Function(MomoSmsCapture capture)
  onIngest;

  @override
  Future<MomoSmsIngestionResult?> ingestCapture({
    required MomoSmsCapture capture,
    String? userId,
  }) {
    return onIngest(capture);
  }
}

class FakeSmsAutoreadCrashlyticsService extends CrashlyticsService {
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

Session smsAutoreadSessionFor(String userId) {
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

SmsMessage smsAutoreadMessage({
  required String sender,
  required String body,
  required DateTime receivedAt,
}) {
  return SmsMessage.fromMap(
    <String, String>{
      'address': sender,
      'body': body,
      'date': receivedAt.millisecondsSinceEpoch.toString(),
    },
    const <SmsColumn>[SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
  );
}

class FakeSmsAutoreadDeviceSettingsService extends DeviceSettingsService {
  @override
  Future<bool> openNfcSettings() async => true;
}

class FakeSmsAutoreadNfcHceService extends NfcHceService {
  @override
  Future<bool> isSupported() async => false;

  @override
  Future<bool> isPaymentRequestActive() async => false;

  @override
  Future<void> stopPaymentRequest() async {}
}

class FakeSmsAutoreadLocationService implements LocationService {
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
