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
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _captureKey = ValueKey('profile-editor-capture');

class _FixtureSmsAccess extends SmsAccessChannel {
  const _FixtureSmsAccess();
  @override
  Future<bool> setEnabled(bool enabled, {String? ownerUserId}) async => enabled;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader(
          'packages/font_awesome_flutter/FontAwesomeBrands',
        )..addFont(
          rootBundle.load(
            'packages/font_awesome_flutter/lib/fonts/Font-Awesome-7-Brands-Regular-400.otf',
          ),
        ))
        .load();
  });

  Future<CollectRepository> pumpEditor(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double scale = 1,
    ThemeMode theme = ThemeMode.dark,
    double keyboard = 0,
    CollectProfile? profile,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final repository = CollectRepository.fixture(
      profileOverride: profile,
      smsAccessChannel: const _FixtureSmsAccess(),
    );
    final router = createAppRouter(initialLocation: '/settings/profile');
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          collectRepositoryProvider.overrideWith((ref) => repository),
          collectThemeModeProvider.overrideWith(
            (ref) => CollectThemeModeController(
              initialMode: theme,
              loadPersistedMode: false,
            ),
          ),
        ],
        child: RepaintBoundary(
          key: _captureKey,
          child: MediaQuery(
            data: MediaQueryData.fromView(tester.view).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: const CollectApp(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  Finder input(String key) => find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(TextField),
  );

  testWidgets('verified WhatsApp is separate from the country action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpEditor(tester);
      final whatsapp = tester.getSemantics(
        find.byKey(const ValueKey('profile_whatsapp_semantics')),
      );
      expect(whatsapp.flagsCollection.isReadOnly, isTrue);
      expect(whatsapp.flagsCollection.isButton, isFalse);
      expect(whatsapp.label, isNot(contains('Profile country')));
      final country = tester.getSemantics(
        find.byKey(const ValueKey('profile_country_picker')),
      );
      expect(country.flagsCollection.isButton, isTrue);
      expect(country.label, isNot(contains('WhatsApp')));
    } finally {
      semantics.dispose();
    }
  });

  Future<void> capture(WidgetTester tester, String name) async {
    final directory = Platform.environment['COLLECT_PROFILE_CAPTURE_DIR'];
    if (directory == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      await Directory(directory).create(recursive: true);
      await File(
        '$directory/$name.png',
      ).writeAsBytes(png!.buffer.asUint8List());
    });
  }

  const variants = [
    ('compact', Size(320, 740), 1.0, ThemeMode.dark, 0.0),
    ('mobile', Size(390, 844), 1.0, ThemeMode.dark, 0.0),
    ('light', Size(430, 932), 1.0, ThemeMode.light, 0.0),
    ('desktop', Size(1184, 841), 1.0, ThemeMode.dark, 0.0),
    ('large-text', Size(320, 740), 2.0, ThemeMode.dark, 0.0),
    ('landscape', Size(740, 390), 1.0, ThemeMode.dark, 0.0),
    ('keyboard', Size(390, 844), 1.0, ThemeMode.dark, 300.0),
  ];
  for (final size in [const Size(320, 740), const Size(1184, 841)]) {
    testWidgets('diaspora profile has only account number at ${size.width}', (
      tester,
    ) async {
      final repository = await pumpEditor(
        tester,
        size: size,
        profile: const CollectProfile(
          id: 'diaspora-profile',
          publicId: '123456',
          whatsappPhone: '+35699123456',
          countryCode: 'MT',
          currencyCode: 'EUR',
          revolutAccount: '000123456789',
        ),
      );
      expect(find.text('Account number'), findsOneWidget);
      expect(find.text('Revolut'), findsNothing);
      expect(find.text('Revolut.me link'), findsNothing);
      expect(find.text('MoMo number'), findsNothing);
      expect(find.text('Account name'), findsNothing);
      expect(tester.takeException(), isNull);
      await capture(tester, 'diaspora-account-${size.width.toInt()}');
      await tester.enterText(
        input('profile_revolut_account_input'),
        '0001 2345 6790',
      );
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repository.state.currentProfile?.revolutAccount, '000123456790');
      expect(repository.state.currentProfile?.isComplete, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
  for (final variant in variants) {
    testWidgets('profile editor adapts to ${variant.$1}', (tester) async {
      await pumpEditor(
        tester,
        size: variant.$2,
        scale: variant.$3,
        theme: variant.$4,
        keyboard: variant.$5,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Profile complete'), findsNothing);
      expect(find.text('Country is independent from sign-in'), findsNothing);
      expect(find.text('Rwanda uses MoMo'), findsNothing);
      expect(find.text('Back to settings'), findsNothing);
      expect(find.text('Name'), findsNothing);
      expect(find.text('Account name'), findsNothing);
      expect(
        find.byKey(const ValueKey('profile_display_name_input')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('profile_revolut_name_input')),
        findsNothing,
      );
      expect(
        tester
            .widget<FaIcon>(find.byKey(const ValueKey('profile_whatsapp_icon')))
            .icon,
        FontAwesomeIcons.whatsapp.data,
      );
      expect(find.text('Save').hitTestable(), findsOneWidget);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('native_profile_editor')))
            .width,
        lessThanOrEqualTo(430),
      );
      await capture(tester, variant.$1);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('profile_momo_number_input')),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('profile_momo_number_input')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('MoMo edit, revert and save preserve numeric identity', (
    tester,
  ) async {
    final repository = await pumpEditor(tester);
    final original = repository.state.currentProfile!;
    final number = input('profile_momo_number_input');
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.enterText(number, '0788000001');
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    await tester.enterText(number, original.momoNumber);
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.enterText(number, '0788000001');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repository.state.currentProfile!.momoNumber, '0788000001');
    expect(repository.state.currentProfile!.publicId, original.publicId);
    expect(repository.state.currentProfile!.isComplete, isTrue);
    expect(
      repository.state.currentProfile!.whatsappPhone,
      original.whatsappPhone,
    );
    expect(find.text('Profile saved.'), findsOneWidget);
  });

  testWidgets('MoMo validates and infers provider without a selector', (
    tester,
  ) async {
    final repository = await pumpEditor(tester);
    expect(find.text('Mobile Money provider'), findsNothing);
    expect(find.text('MTN MoMo'), findsNothing);
    expect(find.text('Airtel Money'), findsNothing);
    expect(find.text('MoMo receipt access'), findsNothing);
    expect(find.text('Account and session'), findsNothing);
    final number = input('profile_momo_number_input');
    await tester.ensureVisible(number);
    await tester.enterText(number, '072');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid Rwanda MoMo number.'), findsOneWidget);
    expect(repository.state.currentProfile!.momoProvider, 'mtn_momo');
    await tester.ensureVisible(number);
    await tester.enterText(number, '0720000001');
    await tester.pump();
    expect(find.text('Enter a valid Rwanda MoMo number.'), findsNothing);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repository.state.currentProfile!.momoProvider, 'airtel_money');
    expect(repository.state.currentProfile!.momoNumber, '0720000001');
  });

  testWidgets('back protects edits until discard is confirmed', (tester) async {
    final repository = await pumpEditor(tester);
    await tester.enterText(input('profile_momo_number_input'), '0788000001');
    await tester.pump();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(input('profile_momo_number_input'))
          .controller!
          .text,
      '0788000001',
    );
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Account details'), findsOneWidget);
    expect(repository.state.currentProfile!.momoNumber, '0788123456');
  });
}
