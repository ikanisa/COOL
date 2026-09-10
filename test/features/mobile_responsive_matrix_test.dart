import '../fixtures/collect_repository_fixture.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/collect_theme_controller.dart';
import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _captureKey = ValueKey('responsive-matrix-capture');

class _FixtureSmsAccess extends SmsAccessChannel {
  const _FixtureSmsAccess();

  @override
  Future<bool> setEnabled(bool enabled, {String? ownerUserId}) async => enabled;
}

// These are layout simulations with the complete router and shell. They do not
// stand in for the release contract's native keyboard or screen-reader evidence.
const _routes = [
  _Route('home', '/home', 'RWF 35,000'),
  _Route('groups', '/groups', 'Groups'),
  _Route('profile-edit', '/settings/profile', 'Profile', action: 'Save'),
  _Route(
    'contribution',
    '/groups/qa-private-group/contribute',
    'How much?',
    action: 'Continue to MoMo',
  ),
  _Route(
    'diaspora-contribution',
    '/groups/qa-private-group/contribute',
    'How much?',
    action: 'Review transfer',
    diaspora: true,
  ),
  _Route('settings', '/settings', 'Account details'),
  _Route('settings-permissions', '/settings/permissions', 'App permissions'),
  _Route('auth', '/auth', "Let's get started!", action: 'Send WhatsApp code'),
];

const _variants = [
  _Variant('compact-320', Size(320, 568)),
  _Variant('large-phone-430', Size(430, 932)),
  _Variant('tablet-800', Size(800, 1100)),
  _Variant('landscape', Size(740, 360)),
  _Variant('light', Size(390, 844), theme: ThemeMode.light),
  _Variant('large-text-200', Size(320, 568), scale: 2),
  _Variant('reduced-motion', Size(390, 844), reducedMotion: true),
];

void main() {
  const permissionChannel = MethodChannel(
    'flutter.baseflow.com/permissions/methods',
  );
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          permissionChannel,
          (call) async => call.method == 'checkPermissionStatus' ? 0 : null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, null);
  });
  setUpAll(() async {
    for (final font in {
      'Inter': 'assets/typefaces/Inter-Variable.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  for (final route in _routes) {
    for (final variant in _variants) {
      testWidgets('${route.name} / ${variant.name}', (tester) async {
        await _open(tester, route, variant);
        expect(find.text(route.marker), findsWidgets);
        expect(tester.takeException(), isNull);
        await _capture(tester, '${route.name}-${variant.name}');
        if (route.action case final String action) {
          final target = find.text(action);
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          expect(target.hitTestable(), findsOneWidget);
          expect(
            tester.renderObject<RenderParagraph>(target).didExceedMaxLines,
            isFalse,
          );
        }
        // Exercise lazy content below the first viewport as well.
        for (var step = 0; step < 6; step++) {
          final scrollables = tester.stateList<ScrollableState>(
            find.byType(Scrollable),
          );
          for (final scrollable in scrollables) {
            final position = scrollable.position;
            if (position.axis == Axis.vertical &&
                position.hasContentDimensions) {
              position.jumpTo(position.maxScrollExtent);
            }
          }
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.takeException(), isNull);
        }
        await _capture(tester, '${route.name}-${variant.name}-scrolled');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    }
  }

  testWidgets('group description keeps its full label at 200% text', (
    tester,
  ) async {
    const route = _Route('group-create', '/groups/create', 'Create group');
    await _open(
      tester,
      route,
      const _Variant('large-text-200', Size(320, 568), scale: 2),
    );
    final label = find.text('Description, optional');
    await Scrollable.ensureVisible(tester.element(label), alignment: 0.5);
    await tester.pumpAndSettle();
    expect(
      tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
      isFalse,
    );
    expect(label.hitTestable(), findsOneWidget);
    await _capture(tester, 'group-create-large-text-200-description');
    await tester.enterText(
      find.byType(TextField).last,
      'Saving for our shared goals',
    );
    await tester.pumpAndSettle();
    expect(
      tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
      isFalse,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  final forms = [
    ..._routes.where((route) => route.action != null),
    const _Route(
      'diaspora-profile',
      '/settings/profile',
      'Profile',
      action: 'Save',
      diaspora: true,
    ),
    const _Route(
      'group-create',
      '/groups/create',
      'Create group',
      action: 'Continue',
    ),
  ];
  for (final route in forms) {
    for (final landscape in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        final variant = _Variant(
          'keyboard-${landscape ? 'landscape' : 'compact'}-${scale.toInt() * 100}',
          landscape ? const Size(740, 360) : const Size(320, 568),
          scale: scale,
        );
        testWidgets('${route.name} / ${variant.name}', (tester) async {
          await _open(tester, route, variant);
          // ListView children beyond the cache extent are not built yet.
          for (
            var step = 0;
            find.byType(TextField).evaluate().isEmpty && step < 12;
            step++
          ) {
            for (final scrollable in tester.stateList<ScrollableState>(
              find.byType(Scrollable),
            )) {
              if (scrollable.position.axis != Axis.vertical) continue;
              scrollable.position.jumpTo(
                (scrollable.position.pixels + 160).clamp(
                  0,
                  scrollable.position.maxScrollExtent,
                ),
              );
            }
            await tester.pump();
          }
          final field = find.byType(TextField).first;
          await Scrollable.ensureVisible(tester.element(field), alignment: 0.5);
          await tester.pumpAndSettle();
          await tester.tap(field);
          // Model a visible software keyboard, rather than resizing the whole
          // app; nested scaffolds must agree on the remaining viewport.
          tester.view.viewInsets = FakeViewPadding(
            bottom: landscape ? 240 : 280,
          );
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            tester
                .widget<EditableText>(
                  find.descendant(
                    of: field,
                    matching: find.byType(EditableText),
                  ),
                )
                .focusNode
                .hasFocus,
            isTrue,
            reason: 'Keyboard resizing must retain the active field',
          );
          await Scrollable.ensureVisible(tester.element(field), alignment: 0.5);
          await tester.pumpAndSettle();
          await _capture(tester, '${route.name}-${variant.name}-focused');
          expect(field.hitTestable(), findsOneWidget);
          await tester.enterText(field, switch (route.name) {
            'auth' || 'profile-edit' => '788123457',
            'group-create' => 'Kigali savings circle',
            'diaspora-profile' => '000123456780',
            'diaspora-contribution' => '12.34',
            _ => '1234',
          });
          await tester.pumpAndSettle();
          await _capture(tester, '${route.name}-${variant.name}-input');
          final action = find.text(route.action!);
          // At large text with a landscape keyboard, the profile action is
          // beyond the sliver cache. Scroll the form to build it before asking
          // ensureVisible to resolve its element.
          await tester.scrollUntilVisible(
            action,
            80,
            scrollable: find
                .ancestor(of: field, matching: find.byType(Scrollable))
                .first,
          );
          await tester.pumpAndSettle();
          expect(action.hitTestable(), findsOneWidget);
          final rect = tester.getRect(action);
          expect(
            rect.bottom,
            lessThanOrEqualTo(
              variant.size.height - tester.view.viewInsets.bottom,
            ),
          );
          expect(tester.takeException(), isNull);
          await _capture(tester, '${route.name}-${variant.name}-action');
          if (route.name == 'profile-edit' ||
              route.name == 'diaspora-profile') {
            final container = ProviderScope.containerOf(tester.element(action));
            await tester.tap(action);
            await tester.pumpAndSettle();
            final profile = container
                .read(collectRepositoryProvider)
                .currentProfile!;
            expect(
              route.diaspora ? profile.revolutAccount : profile.momoNumber,
              route.diaspora ? '000123456780' : '0788123457',
            );
            expect(find.text('Profile saved.'), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        });
      }
    }
  }
}

Future<void> _open(WidgetTester tester, _Route route, _Variant variant) async {
  tester.view.physicalSize = variant.size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = variant.scale;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(
        disableAnimations: variant.reducedMotion,
        reduceMotion: variant.reducedMotion,
      );
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final repository = FixtureCollectRepository(
    seeded: route.name != 'auth',
    smsAccessChannel: const _FixtureSmsAccess(),
    profileOverride: route.diaspora
        ? const CollectProfile(
            id: 'local-user',
            publicId: '038491',
            whatsappPhone: '+250788123456',
            countryCode: 'DE',
            currencyCode: 'EUR',
            revolutAccount: '000123456789',
          )
        : null,
  );
  final router = createAppRouter(initialLocation: route.path);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appRouterProvider.overrideWithValue(router),
        collectRepositoryProvider.overrideWith((ref) => repository),
        collectThemeModeProvider.overrideWith(
          (ref) => CollectThemeModeController(
            initialMode: variant.theme,
            loadPersistedMode: false,
          ),
        ),
      ],
      child: const RepaintBoundary(key: _captureKey, child: CollectApp()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final output = Platform.environment['COLLECT_RESPONSIVE_CAPTURE_DIR'];
  if (output == null) return;
  final context = tester.element(find.byKey(_captureKey));
  final providers = tester
      .widgetList<Image>(find.byType(Image))
      .map((image) => image.image)
      .toSet();
  await tester.runAsync(() async {
    for (final provider in providers) {
      await precacheImage(provider, context);
    }
  });
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory(output)..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

class _Route {
  const _Route(
    this.name,
    this.path,
    this.marker, {
    this.action,
    this.diaspora = false,
  });
  final String name;
  final String path;
  final String marker;
  final String? action;
  final bool diaspora;
}

class _Variant {
  const _Variant(
    this.name,
    this.size, {
    this.scale = 1,
    this.theme = ThemeMode.dark,
    this.reducedMotion = false,
  });
  final String name;
  final Size size;
  final double scale;
  final ThemeMode theme;
  final bool reducedMotion;
}
