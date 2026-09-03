import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/providers/collect_app_state.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final country in ['RW', 'DE']) {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets(
        '$country / $platform only offers supported SMS capture',
        (tester) async {
          final repository = CollectRepository.fixture(
            profileOverride: CollectProfile(
              id: 'local-user',
              publicId: '038491',
              whatsappPhone: '+250788123456',
              countryCode: country,
              currencyCode: country == 'RW' ? 'RWF' : 'EUR',
              revolutLink: 'https://revolut.me/synthetic',
              revolutAccount: 'Synthetic account',
            ),
          );
          final router = createAppRouter(
            initialLocation: '/settings/permissions',
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                appRouterProvider.overrideWithValue(router),
                collectRepositoryProvider.overrideWith((ref) => repository),
              ],
              child: const CollectApp(),
            ),
          );
          await tester.pumpAndSettle();
          final supported =
              country == 'RW' && platform == TargetPlatform.android;
          expect(
            find.text('MoMo receipt SMS'),
            supported ? findsOneWidget : findsNothing,
          );
          expect(
            find.text('Review and allow'),
            supported ? findsOneWidget : findsNothing,
          );
          if (!supported) {
            expect(find.text('Rwanda MoMo receipts only'), findsNothing);
            expect(find.textContaining('on this Android device'), findsNothing);
          }
          expect(find.text('Notifications'), findsOneWidget);
          await tester.scrollUntilVisible(
            find.text('Camera'),
            150,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(find.text('Camera'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(platform),
      );
    }
  }

  test('iOS ignores a cached Android SMS-granted flag', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final repository = _EnabledSmsFixture();
    final container = ProviderContainer(
      overrides: [collectRepositoryProvider.overrideWith((ref) => repository)],
    );
    addTearDown(container.dispose);
    expect(
      container.read(smsPermissionStatusProvider),
      SmsPermissionStatus.unavailable,
    );
  });

  for (final width in [320.0, 430.0]) {
    testWidgets(
      'permission status does not squeeze large titles at width $width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 844);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final router = createAppRouter(
          initialLocation: '/settings/permissions',
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appRouterProvider.overrideWithValue(router),
              collectRepositoryProvider.overrideWith(
                (ref) => CollectRepository.fixture(),
              ),
            ],
            child: const CollectApp(),
          ),
        );
        await tester.pumpAndSettle();
        final title = find.text('Notifications');
        final paragraph = tester.renderObject<RenderParagraph>(title);
        expect(
          paragraph.getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 13),
          ),
          hasLength(1),
          reason: 'The status must not force a break within Notifications.',
        );
        expect(
          tester
              .getTopLeft(
                find.byKey(const ValueKey('permission_status_Notifications')),
              )
              .dy,
          greaterThan(tester.getBottomLeft(title).dy),
        );
        expect(
          find.text('Control only the device access Collect needs.'),
          findsNothing,
        );
        await tester.scrollUntilVisible(
          find.text('Camera'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Camera').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }
}

class _EnabledSmsFixture extends CollectRepository {
  _EnabledSmsFixture() : super.fixture() {
    state = state.copyWith(smsAccessEnabled: true);
  }
}
