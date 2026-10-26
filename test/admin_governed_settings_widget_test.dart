import 'dart:async';
import 'dart:convert';
import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/core/admin_governed_settings_models.dart';
import 'package:collect_app/admin/core/admin_governed_settings_sdk.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'admin_action_session_test.dart' as auth;
import 'support/settings_fixture.dart' as f;

const owner = AdminIdentity(
  userId: f.actor,
  displayName: 'Synthetic owner',
  roles: ['platform_owner'],
  permissions: ['settings.read', 'settings.manage', 'audit.read'],
);

class Repository extends Fake implements AdminRepositoryBase {
  Repository(this.api);
  final AdminGovernedSettingsApi api;
  @override
  AdminGovernedSettingsApi get governedSettings => api;
  @override
  Future<AdminRuntimeConfig?> runtimeConfig() async =>
      const AdminRuntimeConfig(navigationItems: [], queueSpecs: []);
}

void main() {
  late CollectCloudflareClient client;
  late f.SettingsApiFake api;
  late f.MemorySettingsStore store;
  late ProviderContainer container;
  final authority = StateProvider<Future<AdminIdentity?>>((_) async => owner);
  final clock = StateProvider<DateTime>((_) => f.at);
  setUp(() async {
    client = CollectCloudflareClient(
      'https://synthetic.invalid',
      httpClient: MockClient((r) async {
        final values = (jsonDecode(r.body)['token'] as String).split('|');
        return auth.response(auth.authReceipt(values[0], values[1]));
      }),
    );
    await auth.session(client, f.sessionA);
    api = f.SettingsApiFake();
    store = f.MemorySettingsStore();
    container = ProviderContainer(
      overrides: [
        collectBackendClientProvider.overrideWithValue(client),
        adminRepositoryProvider.overrideWithValue(Repository(api)),
        adminIdentityProvider.overrideWith((ref) => ref.watch(authority)),
        adminRealtimeSubscriptionProvider.overrideWith((ref) {}),
        adminSettingsCheckpointStoreProvider.overrideWithValue(store),
        adminClockProvider.overrideWith((ref) {
          final at = ref.watch(clock);
          return () => at;
        }),
      ],
    );
    await container.read(adminIdentityProvider.future);
    container.read(adminAuthSessionScopeProvider);
  });
  tearDown(() async {
    container.dispose();
    await client.dispose();
  });
  Future<void> mount(
    WidgetTester tester, {
    double width = 1250,
    double scale = 1,
    bool route = false,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final Widget app;
    if (route) {
      final router = container.read(adminRouterProvider);
      router.go('/admin/settings');
      app = MaterialApp.router(
        theme: CollectTheme.light(),
        routerConfig: router,
      );
    } else {
      app = MaterialApp(
        theme: CollectTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: AdminGovernedSettingsPage(
            initialFamily: f.family.key,
            initialIdentity: f.identity,
          ),
        ),
      );
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: app),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
  }

  Future<void> click(WidgetTester t, Finder finder) async {
    await t.ensureVisible(finder);
    await t.pump();
    await t.tap(finder);
    await t.pump();
    await t.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await t.pumpAndSettle();
  }

  Future<void> draft(
    WidgetTester t, {
    String label = 'Reviewed reason label',
    String reason = 'Accountable setting update',
  }) async {
    await click(t, find.byKey(const ValueKey('settings-change-label')));
    await t.enterText(
      find.byKey(const ValueKey('settings-field-label')),
      label,
    );
    await t.enterText(find.byKey(const Key('settings-reason')), reason);
    await click(t, find.text('Review change'));
  }

  testWidgets(
    'actual authenticated Settings route uses dedicated typed workspace',
    (t) async {
      await mount(t, route: true);
      expect(find.byType(AdminGovernedSettingsPage), findsOneWidget);
      expect(find.text('Settings family'), findsOneWidget);
      expect(find.text('Open identity'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'typed editor captures immutable preview and one durable original save',
    (t) async {
      AdminSettingsPreparedUpdate? sent;
      api.onUpdate = (i) async {
        sent = i;
        return AdminSettingsReceipt.parse(f.receiptJson(i));
      };
      await mount(t);
      expect(find.text('Current setting'), findsOneWidget);
      expect(find.text('Change history'), findsOneWidget);
      await draft(t);
      expect(find.text('Review setting change'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('Reviewed reason label'),
        ),
        findsOneWidget,
      );
      await click(t, find.text('Save original request'));
      expect(api.updates, 1);
      expect(jsonDecode(sent!.patchJson), {'label': 'Reviewed reason label'});
      expect(store.originals.length, 1);
      expect(store.resolutions.length, 1);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'nullable field clear is explicit and invalid reason never opens preview',
    (t) async {
      await mount(t);
      await click(t, find.byKey(const ValueKey('settings-change-description')));
      await click(t, find.text('Clear description'));
      await t.enterText(find.byKey(const Key('settings-reason')), 'short');
      await click(t, find.text('Review change'));
      expect(find.text('Review setting change'), findsNothing);
      expect(api.updates, 0);
      await t.enterText(
        find.byKey(const Key('settings-reason')),
        'Clear obsolete description',
      );
      await click(t, find.text('Review change'));
      expect(find.textContaining('"description": null'), findsOneWidget);
      await click(t, find.text('Cancel'));
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'integer input error denies preparation and unsafe original expiry denies save',
    (t) async {
      await mount(t);
      await click(
        t,
        find.byKey(const ValueKey('settings-change-display_order')),
      );
      await t.enterText(
        find.byKey(const ValueKey('settings-field-display_order')),
        '1.5',
      );
      await t.enterText(
        find.byKey(const Key('settings-reason')),
        'Reviewed display order',
      );
      await click(t, find.text('Review change'));
      expect(find.text('Review setting change'), findsNothing);
      expect(api.updates, 0);
      await t.enterText(
        find.byKey(const ValueKey('settings-field-display_order')),
        '101',
      );
      await click(t, find.text('Review change'));
      container.read(clock.notifier).state = f.at.add(
        const Duration(seconds: 91),
      );
      await t.pump(const Duration(seconds: 1));
      final save = t.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save original request'),
      );
      expect(save.onPressed, isNull);
      await click(t, find.text('Cancel'));
      expect(api.updates, 0);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'permission refresh removes draft dialog immediately and late future cannot restore it',
    (t) async {
      await mount(t);
      await draft(t);
      final held = Completer<AdminIdentity?>();
      container.read(authority.notifier).state = held.future;
      await t.pump();
      await t.pump(const Duration(milliseconds: 250));
      expect(find.text('Review setting change'), findsNothing);
      expect(api.updates, 0);
      held.complete(owner);
      await t.pumpAndSettle();
      expect(find.text('Review setting change'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'uncertain response exposes original lookup action and no resend control',
    (t) async {
      api.onUpdate = (_) async => throw TimeoutException('PRIVATE_CANARY');
      await mount(t);
      await draft(t);
      await click(t, find.text('Save original request'));
      expect(find.text('Original requests to investigate'), findsOneWidget);
      expect(find.text('Check original'), findsOneWidget);
      expect(api.updates, 1);
      expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
      final original = container
          .read(adminSettingsControllerProvider)
          .pending
          .single;
      api.onLookup = (b) async => AdminSettingsLookup.parse(
        f.lookupJson(b, f.at, status: 'in_progress'),
        b,
      );
      await click(t, find.text('Check original'));
      expect(api.lookups, 1);
      expect(
        container.read(adminSettingsControllerProvider).pending.single.digest,
        original.digest,
      );
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Review change'),
            )
            .onPressed,
        isNull,
      );
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'independent audit view works for known identity without settings.read',
    (t) async {
      container.read(authority.notifier).state = Future.value(
        const AdminIdentity(
          userId: f.actor,
          displayName: 'Audit owner',
          roles: ['platform_owner'],
          permissions: ['audit.read'],
        ),
      );
      await container.read(adminIdentityProvider.future);
      await mount(t);
      expect(find.text('Change history'), findsOneWidget);
      expect(find.text('Current setting'), findsNothing);
      expect(find.textContaining('Revision 1 → 2'), findsOneWidget);
      expect(api.updates, 0);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('expired current sample disables editor until explicit refresh', (
    t,
  ) async {
    await mount(t);
    container.read(clock.notifier).state = f.at.add(
      const Duration(seconds: 61),
    );
    await t.pump(const Duration(seconds: 1));
    expect(find.textContaining('This view expired.'), findsOneWidget);
    expect(
      t.widget<TextField>(find.byKey(const Key('settings-reason'))).enabled,
      isFalse,
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'history pages use paired immutable cursor and retain newer navigation',
    (t) async {
      final calls = <AdminSettingsHistoryCursor?>[];
      api.onHistory = (family, identity, limit, before) async {
        calls.add(before);
        final h = f.observed('history');
        final template = Map<String, dynamic>.from(
          (h['rows'] as List).first as Map,
        );
        h['limit'] = limit;
        h['checked_at'] = settingsUtc(f.at);
        h['sample_valid_until'] = settingsUtc(
          f.at.add(const Duration(seconds: 60)),
        );
        final start = before == null ? 1 : 21, count = before == null ? 20 : 1;
        h['rows'] = [
          for (var i = start; i < start + count; i++)
            {
              ...template,
              'event_id':
                  '99850000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
              'recorded_at': settingsUtc(f.at.subtract(Duration(seconds: i))),
              'previous_revision': 40 - i,
              'revision': 41 - i,
            },
        ];
        h['next_cursor'] = before == null
            ? {
                'recorded_at': (h['rows'] as List).last['recorded_at'],
                'event_id': (h['rows'] as List).last['event_id'],
              }
            : null;
        return AdminSettingsHistory.parse(
          h,
          family,
          identity,
          limit: limit,
          before: before,
        );
      };
      await mount(t);
      await click(t, find.text('Older changes'));
      expect(calls.last!.eventId, '99850000-0000-4000-8000-000000000020');
      expect(
        calls.last!.recordedAt,
        f.at.subtract(const Duration(seconds: 20)),
      );
      expect(find.text('Newer changes'), findsOneWidget);
      await click(t, find.text('Newer changes'));
      expect(find.text('Older changes'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  for (final spec in [(320.0, 1.0), (450.0, 2.0)]) {
    testWidgets(
      'narrow ${spec.$1} large-text ${spec.$2} labels and keyboard controls do not overflow',
      (t) async {
        final semantics = t.ensureSemantics();

        await mount(t, width: spec.$1, scale: spec.$2);
        expect(t.takeException(), isNull);
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        expect(FocusManager.instance.primaryFocus, isNotNull);
        await t.ensureVisible(find.byKey(const Key('settings-reason')));
        await t.pump();
        expect(find.text('Review change'), findsOneWidget);
        expect(find.text('Refresh current value'), findsOneWidget);
        expect(t.takeException(), isNull);
        semantics.dispose();
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
