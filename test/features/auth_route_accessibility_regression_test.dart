import 'dart:ui' show SemanticsFlag;

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/features/auth/widgets/auth_screen_widgets.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
            onCountryTap: () {},
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
          appRouterProvider.overrideWithValue(router),
          collectRepositoryProvider.overrideWith(
            (ref) => CollectRepository.fixture(seeded: false),
          ),
        ],
        child: const CollectApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Let's get started!"), findsOneWidget);
    expect(find.text('Home'), findsNothing);
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
    expect(redirect('/auth'), isNull);
    expect(redirect('/c/public-group'), isNull);
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
}
