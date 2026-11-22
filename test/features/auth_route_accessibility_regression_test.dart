import '../fixtures/collect_repository_fixture.dart';
import '../fixtures/auth_otp_gateway_fixture.dart';

import 'dart:ui' show SemanticsFlag;

import 'package:collect_app/core/cloudflare/auth_otp_gateway.dart';
import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:collect_app/features/auth/widgets/auth_screen_widgets.dart';
import 'package:collect_app/features/auth/auth_screen.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SignedOutPublicRepository extends FixtureCollectRepository {
  _SignedOutPublicRepository() : super() {
    state = CollectState(
      currentProfile: null,
      collections: state.collections,
      paymentIntents: const [],
      contributions: const [],
      collectionSummaries: const {},
    );
  }
}

void main() {
  testWidgets('Pixel auth CTA remains readable at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectBackendClientProvider.overrideWithValue(null),
          authOtpGatewayProvider.overrideWithValue(
            FixtureAuthOtpGateway(enabled: true),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: AuthScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await selectWhatsAppSignIn(tester);
    final label = tester.widget<Text>(find.text('Send WhatsApp code'));
    expect(label.maxLines, greaterThanOrEqualTo(2));
    expect(label.softWrap, isTrue);
    expect(
      tester.getSize(find.byKey(const ValueKey('auth_submit_button'))).height,
      greaterThanOrEqualTo(76),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Pixel safe-area dock is fully above keyboard at 200 percent text',
    (tester) async {
      // Actual Pixel capture: 1080x2340, 440dpi (DPR2.75), status/cutout136px,
      // navigation66px and keyboard top1364px. Full-minus-IME is496dp, but
      // the SafeArea form has only446.55dp, below the legacy480dp floor.
      const density = 2.75;
      const screen = Size(1080, 2340);
      const keyboardTop = 1364 / density;
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = density;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = FixtureAuthOtpGateway(enabled: false);
      final metrics = ValueNotifier<MediaQueryData>(
        const MediaQueryData(
          size: Size(1080 / density, 2340 / density),
          devicePixelRatio: density,
          padding: EdgeInsets.only(top: 136 / density, bottom: 66 / density),
          viewPadding: EdgeInsets.only(
            top: 136 / density,
            bottom: 66 / density,
          ),
          textScaler: TextScaler.linear(1),
        ),
      );
      addTearDown(metrics.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectBackendClientProvider.overrideWithValue(null),
            authOtpGatewayProvider.overrideWithValue(gateway),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            builder: (context, child) => ValueListenableBuilder<MediaQueryData>(
              valueListenable: metrics,
              builder: (context, data, _) =>
                  MediaQuery(data: data, child: child!),
            ),
            home: const AuthScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final authState = tester.state(find.byType(AuthScreen));
      final email = find.byKey(const ValueKey('auth_email_input'));
      final submit = find.byKey(const ValueKey('auth_submit_button'));
      final action = find.descendant(
        of: submit,
        matching: find.byType(TextButton),
      );
      expect(email, findsOneWidget);
      expect(tester.widget<TextButton>(action).onPressed, isNull);
      // Match the physical journey: focus/type while the normal-size field is
      // built, then open the keyboard and enlarge the same mounted route.
      await tester.tap(email);
      await tester.enterText(email, 'ba');
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(action).onPressed, isNull);
      await tester.enterText(email, 'qa@example.invalid');
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(action).onPressed, isNotNull);
      final editor = tester.widget<EditableText>(
        find.descendant(of: email, matching: find.byType(EditableText)),
      );
      expect(editor.focusNode.hasFocus, isTrue);

      metrics.value = metrics.value.copyWith(
        padding: const EdgeInsets.only(top: 136 / density),
        viewInsets: const EdgeInsets.only(bottom: 976 / density),
      );
      await tester.pumpAndSettle();
      metrics.value = metrics.value.copyWith(
        textScaler: const TextScaler.linear(2),
      );
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(AuthScreen)), same(authState));
      expect(editor.controller.text, 'qa@example.invalid');
      expect(editor.focusNode.hasFocus, isTrue);
      expect(tester.widget<TextButton>(action).onPressed, isNotNull);

      // Do not manually ensureVisible/scroll the dock: that masks the captured
      // trigger defect. The whole control, rather than only its center/label,
      // must fit above the IME after the route's ordinary reveal behavior.
      final actionRect = tester.getRect(submit);
      expect(actionRect.top, greaterThanOrEqualTo(136 / density));
      expect(
        actionRect.bottom,
        lessThanOrEqualTo(keyboardTop),
        reason: 'The complete primary-action pill must remain above the IME',
      );
      expect(actionRect.left, greaterThanOrEqualTo(0));
      expect(actionRect.right, lessThanOrEqualTo(screen.width / density));
      expect(actionRect.height, greaterThanOrEqualTo(76));
      expect(MediaQuery.textScalerOf(tester.element(submit)).scale(16), 32);
      expect(editor.controller.text, 'qa@example.invalid');
      expect(gateway.sends, 0);
      expect(gateway.verifications, 0);
      expect(tester.takeException(), isNull);
      // Intentionally no primary-action tap, OTP, CAPTCHA or provider request.
    },
  );

  testWidgets('phone input exposes its own actionable semantics label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: AuthPhoneEntry(
            controller: controller,
            countryCode: '+250',
            onChanged: () {},
          ),
        ),
      ),
    );

    final phoneField = find.semantics.byFlag(SemanticsFlag.isTextField);
    expect(phoneField, findsOne);
    expect(
      phoneField.evaluate().single.getSemanticsData().tooltip,
      'WhatsApp phone number',
    );
    tester.semantics.setText(phoneField, '781234567');
    await tester.pump();
    expect(controller.text, '781234567');

    semantics.dispose();
  });

  testWidgets('mobile input exposes its visual label to accessibility', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: CollectMobileInputField(
            key: const ValueKey('group_name_field'),
            controller: controller,
            icon: Icons.group,
            label: 'Group name',
          ),
        ),
      ),
    );

    final textField = find.semantics.byFlag(SemanticsFlag.isTextField);
    expect(textField, findsOne);
    expect(
      textField.evaluate().single.getSemanticsData().tooltip,
      'Group name',
    );
    tester.semantics.setText(textField, 'UAT group');
    await tester.pump();
    expect(controller.text, 'UAT group');
    semantics.dispose();
  });

  testWidgets('empty member state cannot render the protected shell', (
    tester,
  ) async {
    final router = createAppRouter(
      initialLocation: '/home',
      routeRedirect: (state) => collectAuthenticationRedirect(
        uri: state.uri,
        hasProfile: false,
        isLoading: false,
      ),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectBackendClientProvider.overrideWithValue(null),
          appRouterProvider.overrideWithValue(router),
          collectRepositoryProvider.overrideWith(
            (ref) => FixtureCollectRepository(seeded: false),
          ),
        ],
        child: const CollectApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Let's get started!"), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('signed-out visitor can inspect a public MoMo contribution', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _SignedOutPublicRepository();
    final router = createAppRouter(
      initialLocation: '/groups/col-public-savings-fixture/contribute',
      routeRedirect: (state) => collectAuthenticationRedirect(
        uri: state.uri,
        hasProfile: repository.state.currentProfile != null,
        isLoading: repository.state.isLoading,
      ),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectBackendClientProvider.overrideWithValue(null),
          appRouterProvider.overrideWithValue(router),
          collectRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: const CollectApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('How much?'), findsOneWidget);
    expect(find.text('MoMo contribution'), findsNothing);
    expect(find.text('IKANISA LTD'), findsOneWidget);
    expect(find.text('41258'), findsOneWidget);
    expect(find.textContaining('MTN MoMo'), findsNothing);
    expect(find.text('Bank transfer'), findsNothing);
    expect(find.text("Let's get started!"), findsNothing);
  });

  test('route guard preserves only public entry points before sign-in', () {
    String? redirect(String location) => collectAuthenticationRedirect(
      uri: Uri.parse(location),
      hasProfile: false,
      isLoading: false,
    );

    expect(redirect('/home'), '/auth');
    expect(redirect('/groups/create'), '/auth');
    expect(redirect('/settings/account'), '/auth');
    expect(redirect('/'), '/auth');
    expect(redirect('/auth'), isNull);
    expect(redirect('/c/public-group'), isNull);
    expect(redirect('/groups'), isNull);
    expect(redirect('/contribute'), isNull);
    expect(redirect('/groups/public-id'), isNull);
    expect(redirect('/groups/public-id/contribute'), isNull);
    expect(redirect('/groups/public-id/share'), isNull);
    expect(redirect('/groups/public-id/manage'), '/auth');
  });

  test('route guard holds protected content while profile state loads', () {
    final loadingRedirect = collectAuthenticationRedirect(
      uri: Uri.parse('/home'),
      hasProfile: false,
      isLoading: true,
    );
    final heldSplash = Uri.parse(loadingRedirect!);

    expect(heldSplash.path, '/');
    expect(heldSplash.queryParameters['holdSplash'], '1');
    expect(heldSplash.queryParameters['next'], '/home');
    expect(
      collectAuthenticationRedirect(
        uri: heldSplash,
        hasProfile: false,
        isLoading: false,
      ),
      '/auth',
    );
    expect(
      collectAuthenticationRedirect(
        uri: heldSplash,
        hasProfile: true,
        isLoading: false,
      ),
      '/home',
    );
  });

  test('successful authentication returns to a safe public contribution', () {
    expect(
      collectAuthenticationRedirect(
        uri: Uri.parse('/auth?next=%2Fgroups%2Fpublic-id%2Fcontribute'),
        hasProfile: true,
        isLoading: false,
      ),
      '/groups/public-id/contribute',
    );
    expect(
      collectAuthenticationRedirect(
        uri: Uri.parse('/auth?next=https%3A%2F%2Fevil.example'),
        hasProfile: true,
        isLoading: false,
      ),
      '/home',
    );
  });
}
