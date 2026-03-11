import 'package:cool_app/core/services/momo_sms_policy_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('android momo sms auto-read is disabled by default', () {
    final service = MomoSmsPolicyService.instance;

    expect(service.isSupportedPlatform, isTrue);
    expect(service.isBuildEnabled, isFalse);
    expect(service.isRuntimeImplemented, isFalse);
    expect(service.isFeatureAvailable, isFalse);
  });
}
