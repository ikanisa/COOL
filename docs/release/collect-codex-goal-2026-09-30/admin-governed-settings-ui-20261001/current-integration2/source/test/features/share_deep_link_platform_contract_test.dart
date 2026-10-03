import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android handles verified group and app share routes', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:autoVerify="true"'));
    expect(manifest, contains('android:pathPrefix="/c/"'));
    expect(manifest, contains('android:pathPrefix="/invite/"'));
    expect(manifest, contains('android:path="/app"'));
    expect(manifest, contains('android:scheme="collect"'));
    expect(manifest, isNot(contains('android:pathPrefix="/c" />')));
  });

  test('iOS handles universal links and the explicit native-open fallback', () {
    final entitlements = File(
      'ios/Runner/Runner.entitlements',
    ).readAsStringSync();
    final info = File('ios/Runner/Info.plist').readAsStringSync();
    final association = File(
      'web/.well-known/apple-app-site-association',
    ).readAsStringSync();

    expect(entitlements, contains('applinks:collect.ikanisa.com'));
    expect(info, contains('<key>CFBundleURLSchemes</key>'));
    expect(info, contains('<string>collect</string>'));
    expect(association, contains('"/c/*"'));
    expect(association, contains('"/invite/*"'));
    expect(association, contains('"/app"'));
  });

  test('public share landing selects the exact production store listing', () {
    final builder = File(
      'scripts/public_static_site_build.rb',
    ).readAsStringSync();

    expect(
      builder,
      contains('https://play.google.com/store/apps/details?id=app.cool.mobile'),
    );
    expect(builder, contains('APPLE_APP_STORE_ID = "6783960331"'));
    expect(
      builder,
      contains('https://apps.apple.com/app/id#{APPLE_APP_STORE_ID}'),
    );
    expect(builder, contains('data-collect-store-link'));
    expect(builder, contains('const isIOS ='));
    expect(builder, contains('const isAndroid ='));
    expect(builder, contains('name="apple-itunes-app"'));
  });
}
