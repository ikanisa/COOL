import 'dart:convert';
import 'dart:io';

import 'package:collect_app/features/collections/group_creation_platform.dart';
import 'package:collect_app/features/landing/collect_landing_page.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final registryFile = File('content/product/collect_capabilities.json');
  final registry = jsonDecode(registryFile.readAsStringSync()) as Map;

  test('Flutter public facts and pages consume the exact current registry', () {
    expect(
      collectPublicCapabilityRegistrySha256,
      sha256.convert(registryFile.readAsBytesSync()).toString(),
    );
    for (final row in registry['capabilities'] as List) {
      final capability = collectPublicCapabilities[row['id']]!;
      expect(capability.label, row['label']);
      expect(capability.summary, row['summary']);
      expect(capability.availability, row['availability']);
      expect(capability.ownerApproved, false);
    }
    expect(collectPublicHomeCopy, registry['flutter_home']);
    for (final row in registry['flutter_pages'] as List) {
      final page = publicPageForPath(row['path'] as String);
      expect(page.title, row['title']);
      expect(page.intro, row['intro']);
      final sections = row['sections'] as List;
      expect(page.sections.length, sections.length);
      for (var i = 0; i < sections.length; i++) {
        expect(page.sections[i].title, sections[i]['title']);
        expect(page.sections[i].body, sections[i]['body']);
        expect(page.sections[i].bullets, sections[i]['bullets']);
      }
    }
  });

  test('private-group availability matches the real native platform guard', () {
    final capability = collectPublicCapabilities['private_group_creation']!;
    for (final entry in {
      'android': TargetPlatform.android,
      'ios': TargetPlatform.iOS,
    }.entries) {
      expect(
        capability.supportsSourceAction(region: 'RW', platform: entry.key),
        groupCreationPlatformAllowed(isWeb: false, targetPlatform: entry.value),
      );
    }
    expect(
      capability.supportsSourceAction(region: 'RW', platform: 'web'),
      groupCreationPlatformAllowed(
        isWeb: true,
        targetPlatform: TargetPlatform.android,
      ),
    );
  });

  test(
    'iOS web and basic-phone MoMo actions deny the Android-only handoff',
    () {
      for (final platform in ['ios', 'web', 'basic_phone']) {
        final capability = collectPublicCapabilities['momo_ussd']!;
        expect(
          capability.supportsSourceAction(region: 'RW', platform: platform),
          false,
        );
        expect(
          capability.nextAction(region: 'RW', platform: platform).toString(),
          'mailto:info@ikanisa.com',
        );
      }
    },
  );

  test(
    'unapproved supported software does not imply approved availability',
    () {
      final capability = collectPublicCapabilities['momo_ussd']!;
      expect(
        capability.supportsSourceAction(region: 'RW', platform: 'android'),
        true,
      );
      expect(
        capability.hasApprovedAvailability(region: 'RW', platform: 'android'),
        false,
      );
    },
  );

  test('foreign regions and unknown platforms cannot inherit support', () {
    final capability = collectPublicCapabilities['group_records']!;
    expect(
      capability.supportsSourceAction(region: 'MT', platform: 'android'),
      false,
    );
    expect(
      capability.supportsSourceAction(region: 'RW', platform: 'desktop'),
      false,
    );
    expect(
      capability.nextAction(region: 'KE', platform: 'android').toString(),
      'mailto:info@ikanisa.com',
    );
  });

  test(
    'planned and provider-dependent services offer information, not enrollment',
    () {
      for (final id in [
        'basic_phone',
        'credit_readiness',
        'loans',
        'insurance',
      ]) {
        final capability = collectPublicCapabilities[id]!;
        expect(
          capability.supportsSourceAction(region: 'RW', platform: 'android'),
          false,
        );
        expect(
          capability.nextAction(region: 'RW', platform: 'android').toString(),
          'mailto:info@ikanisa.com',
        );
      }
    },
  );

  test(
    'a runtime download override cannot advertise an unregistered service',
    () {
      final normal = collectPublicDownloadAction(
        CollectRuntimeConfig.defaults.appDownloadUrl,
      );
      expect(normal.label, 'Get the App');
      expect(
        normal.href,
        'https://play.google.com/store/apps/details?id=app.cool.mobile',
      );
      final unverified = collectPublicDownloadAction(
        'https://unverified.example/credit/enroll',
      );
      expect(unverified.label, 'Ask about Collect');
      expect(unverified.href, 'mailto:info@ikanisa.com');
    },
  );

  test(
    'current iOS and Android store copy is generated from the same facts',
    () {
      for (final entry in (registry['store_metadata'] as Map).entries) {
        expect(
          File(entry.key as String).readAsStringSync(),
          '${entry.value}\n',
        );
      }
      final ios = File(
        'fastlane/metadata/en-GB/description.txt',
      ).readAsStringSync();
      expect(ios, contains('these actions are not available in the iOS app'));
      expect(ios, isNot(contains('SEPA')));
      expect(ios, isNot(contains('bank-transfer')));
      expect(ios, isNot(contains('Revolut')));
      expect(
        File(
          'fastlane/metadata/android/en-US/full_description.txt',
        ).readAsStringSync(),
        contains(
          'Private-group creation is available only on eligible Android',
        ),
      );
    },
  );

  testWidgets(
    'real public download button forwards only the registered action',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final launches = <String>[];
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        expect(call.method, 'launch');
        launches.add((call.arguments as Map)['url'] as String);
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectRuntimeConfigProvider.overrideWith(
              (_) => CollectRuntimeConfig.defaults,
            ),
          ],
          child: const MaterialApp(home: CollectLandingPage()),
        ),
      );
      expect(find.text(collectPublicHomeCopy['intro']!), findsOneWidget);
      await tester.tap(find.text('Get the App').first);
      await tester.pumpAndSettle();
      expect(launches, [
        collectPublicCapabilities['group_records']!.actionHref,
      ]);
      expect(tester.takeException(), isNull);
    },
  );
}
