import 'dart:convert';

import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:collect_app/features/status/account_legal_screens.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/collect_repository_fixture.dart';

Set<String> _registeredPaths(List<RouteBase> routes, [String parent = '']) {
  final paths = <String>{};
  for (final route in routes) {
    var path = parent;
    if (route is GoRoute) {
      path = route.path.startsWith('/')
          ? route.path
          : '${parent == '/' ? '' : parent}/${route.path}';
      paths.add(path);
    }
    paths.addAll(_registeredPaths(route.routes, path));
  }
  return paths;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('member QA catalogue covers every registered route and alias', () {
    final router = createAppRouter();
    addTearDown(router.dispose);

    expect(
      collectRoutePaths.toSet(),
      _registeredPaths(router.configuration.routes),
    );
    expect(collectRoutePaths.toSet().length, collectRoutePaths.length);
  });

  testWidgets('member route factories and conditional guards are inventoried', (
    tester,
  ) async {
    final router = createAppRouter();
    addTearDown(router.dispose);
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final routes = <String, GoRoute>{};
    void collect(List<RouteBase> children, [String parent = '']) {
      for (final child in children) {
        var path = parent;
        if (child is GoRoute) {
          path = child.path.startsWith('/')
              ? child.path
              : '${parent == '/' ? '' : parent}/${child.path}';
          expect(routes.containsKey(path), isFalse);
          routes[path] = child;
        }
        collect(child.routes, path);
      }
    }

    collect(router.configuration.routes);
    expect(routes.keys.toSet(), collectRoutePaths.toSet());
    final records = <Map<String, Object?>>[];
    try {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        debugDefaultTargetPlatformOverride = platform;
        for (final identity in ['signed_out', 'rwanda', 'diaspora']) {
          final repository = FixtureCollectRepository(
            seeded: identity != 'signed_out',
            fixtureNow: DateTime.utc(2026, 9, 14),
            profileOverride: identity == 'diaspora'
                ? const CollectProfile(
                    id: 'local-user',
                    publicId: '038491',
                    whatsappPhone: '+250788123456',
                    countryCode: 'DE',
                    currencyCode: 'EUR',
                  )
                : null,
          );
          await tester.pumpWidget(
            ProviderScope(
              key: ValueKey('${platform.name}:$identity'),
              overrides: [
                collectRepositoryProvider.overrideWith((ref) => repository),
              ],
              child: MaterialApp(
                theme: ThemeData(platform: platform),
                home: Builder(
                  builder: (context) => const SizedBox(key: ValueKey('scope')),
                ),
              ),
            ),
          );
          final context = tester.element(find.byKey(const ValueKey('scope')));
          for (final entry in routes.entries) {
            final parameters = <String, String>{
              'collectionId': 'qa-private-group',
              'slug': 'qa-private-group',
              'publicId': '038491',
            };
            final location = entry.key.replaceAllMapped(
              RegExp(r':([A-Za-z]+)'),
              (match) => parameters[match[1]]!,
            );
            final uri = Uri.parse(location);
            final state = GoRouterState(
              router.configuration,
              uri: uri,
              matchedLocation: location,
              fullPath: entry.key,
              path: entry.value.path,
              pathParameters: parameters,
              pageKey: ValueKey(entry.key),
            );
            final globalRedirect = collectAuthenticationRedirect(
              uri: uri,
              hasProfile: identity != 'signed_out',
              isLoading: false,
            );
            final routeRedirect = await entry.value.redirect?.call(
              context,
              state,
            );
            final page = entry.value.pageBuilder?.call(context, state);
            final Widget? screen = switch (page) {
              CustomTransitionPage<void>() => page.child,
              CupertinoPage<void>() => page.child,
              null => null,
              _ => throw StateError('Unmapped page factory for ${entry.key}'),
            };
            if (entry.value.redirectOnly) {
              expect(routeRedirect, isNotNull, reason: entry.key);
            } else {
              expect(screen, isNotNull, reason: entry.key);
            }
            for (final redirect in [globalRedirect, routeRedirect]) {
              if (redirect == null) continue;
              final target = Uri.parse(redirect);
              expect(target.hasScheme || target.hasAuthority, isFalse);
              expect(target.path.startsWith('/'), isTrue);
            }
            if (entry.key == '/groups/create') {
              // Metadata creation does not grant Android SMS/payment capability.
              expect(routeRedirect, isNull);
            }
            if (entry.key == '/settings/bank-transfer') {
              expect(
                routeRedirect,
                identity == 'diaspora' ? isNull : '/settings/profile',
              );
            }
            records.add({
              'route': entry.key,
              'location': location,
              'platform': platform.name,
              'identity': identity,
              'screen_type': screen?.runtimeType.toString(),
              'redirect_only': entry.value.redirectOnly,
              'global_redirect': globalRedirect,
              'route_redirect': routeRedirect,
              'effective_first_redirect': globalRedirect ?? routeRedirect,
              'loading_redirect': collectAuthenticationRedirect(
                uri: uri,
                hasProfile: identity != 'signed_out',
                isLoading: true,
              ),
            });
          }
        }
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    expect(records, hasLength(collectRoutePaths.length * 2 * 3));
    if (const bool.fromEnvironment('COLLECT_QA_EXPORT_ROUTES')) {
      // Factories and redirect callbacks only; screens were not mounted.
      // ignore: avoid_print
      print('COLLECT_QA_ROUTE_MAP=${jsonEncode(records)}');
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  test(
    'Admin QA catalogue includes helper-generated list and detail routes',
    () {
      final container = ProviderContainer(
        overrides: [
          adminAuthGuardProvider.overrideWithValue(
            const AdminAuthGuard(isAuthorized: true),
          ),
        ],
      );
      addTearDown(container.dispose);
      final router = container.read(adminRouterProvider);
      addTearDown(router.dispose);

      final registered = _registeredPaths(
        router.configuration.routes,
      ).where((path) => path == '/admin' || path.startsWith('/admin/')).toSet();
      expect(adminRoutePaths.toSet(), registered);
      expect(adminRoutePaths.toSet().length, adminRoutePaths.length);
    },
  );

  testWidgets('native privacy route explains review when policy is unavailable', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    var policyRequested = false;
    final router = createAppRouter(initialLocation: '/settings/legal/privacy');
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          collectBackendClientProvider.overrideWithValue(null),
          collectRepositoryProvider.overrideWith(
            (ref) => FixtureCollectRepository(),
          ),
          collectPolicyDocumentProvider('privacy').overrideWith((ref) async {
            policyRequested = true;
            throw StateError('UNAVAILABLE_POLICY_PROVIDER_DO_NOT_RENDER');
          }),
        ],
        child: const CollectApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      '/settings/legal/privacy',
    );
    expect(policyRequested, isTrue);
    expect(find.byType(LegalScreen), findsOneWidget);
    final choices = find.textContaining('Settings > Security > Delete data');
    expect(choices, findsOneWidget);
    await tester.ensureVisible(choices);
    await tester.pumpAndSettle();
    expect(choices.hitTestable(), findsOneWidget);
    expect(
      find.textContaining('Submitting a request does not delete your account'),
      findsOneWidget,
    );
    expect(
      find.textContaining('receipt records your request for review'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Check request status or contact support for the outcome and any records that need to be retained',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('UNAVAILABLE_POLICY_PROVIDER_DO_NOT_RENDER'),
      findsNothing,
    );
    expect(find.textContaining('signs out after'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
