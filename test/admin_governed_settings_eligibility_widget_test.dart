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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'admin_action_session_test.dart' as auth;
import 'support/settings_fixture.dart' as f;
import 'support/settings_eligibility_fixture.dart' as e;

const owner = AdminIdentity(
  userId: f.actor,
  displayName: 'Synthetic owner',
  roles: ['platform_owner'],
  permissions: [
    'settings.read',
    'settings.manage',
    'audit.read',
    'notifications.read',
    'notifications.manage',
    'collections.moderate',
  ],
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

class ContextApi extends f.SettingsApiFake {
  ContextApi(this.current);
  AdminSettingsControl current;
  @override
  Future<AdminSettingsControl> control(
    AdminSettingsFamily family,
    Map<String, Object?> identity,
  ) async => current;
  @override
  Future<AdminSettingsCatalog> catalog(
    AdminSettingsFamily family, {
    int limit = 25,
    Map<String, Object?>? after,
  }) async {
    return AdminSettingsCatalog.parse(
      {
        'contract_version': 2,
        'scope': 'runtime_controls',
        'family': family.key,
        'checked_at': settingsUtc(f.at),
        'sample_valid_until': settingsUtc(
          f.at.add(const Duration(seconds: 60)),
        ),
        'limit': limit,
        'descriptor': {
          'identity_fields': family.identityFields,
          'writable_fields': family.writableFields,
          'immutable_fields': family.immutableFields,
          'nullable_fields': family.nullableFields,
          'field_types': family.fieldTypes,
          'create_allowed': family.createAllowed,
          'can_manage': true,
        },
        'rows': [],
        'next_cursor': null,
      },
      family,
      limit: limit,
    );
  }

  @override
  Future<AdminSettingsHistory> history(
    AdminSettingsFamily family,
    Map<String, Object?> identity, {
    int limit = 20,
    AdminSettingsHistoryCursor? before,
  }) async {
    final raw = f.observed('history');
    raw['family'] = family.key;
    raw['identity'] = identity;
    raw['limit'] = limit;
    raw['rows'] = [];
    raw['next_cursor'] = null;
    raw['checked_at'] = settingsUtc(f.at);
    raw['sample_valid_until'] = settingsUtc(
      f.at.add(const Duration(seconds: 60)),
    );
    return AdminSettingsHistory.parse(
      raw,
      family,
      identity,
      limit: limit,
      before: before,
    );
  }

  @override
  Future<AdminSettingsEligibility> eligibility(
    AdminSettingsControl control,
    String raw,
  ) async {
    eligibilityReads++;
    return onEligibility != null
        ? onEligibility!(control, raw)
        : AdminSettingsEligibility.parse(
            e.currentEligibility(control, raw),
            control.family,
            control.identity,
            control.revision,
            raw,
          );
  }
}

void main() {
  late CollectCloudflareClient client;
  late ContextApi api;
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
    api = ContextApi(e.control('policy_document_sections'));
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
            initialFamily: api.current.family.key,
            initialIdentity: api.current.identity,
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
    // The editor starts its contextual reader after the first current-control render.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
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

  Future<void> sectionDraft(WidgetTester t) async {
    await click(t, find.byKey(const ValueKey('settings-change-body')));
    await t.enterText(
      find.byKey(const ValueKey('settings-field-body')),
      'Reviewed disclosure',
    );
    await t.enterText(
      find.byKey(const Key('settings-reason')),
      'Review updated disclosure',
    );
  }

  testWidgets(
    'actual current parent context enables draft section and rechecks exact draft before immutable review',
    (t) async {
      final observed = <String>[];
      api.onEligibility = (control, raw) async {
        observed.add(raw);
        return AdminSettingsEligibility.parse(
          e.currentEligibility(control, raw),
          control.family,
          control.identity,
          control.revision,
          raw,
        );
      };
      await mount(t);
      await sectionDraft(t);
      await click(t, find.text('Review change'));
      expect(observed.first, '{}');
      expect(observed.last, '{"body":"Reviewed disclosure"}');
      expect(find.text('Review setting change'), findsOneWidget);
      await click(t, find.text('Save original request'));
      expect(api.updates, 1);
      expect(store.originals.length, 1);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'actual backend parent publication blocker disables section edits and offers fresh investigation',
    (t) async {
      api.onEligibility = (control, raw) async =>
          AdminSettingsEligibility.parse(
            e.currentEligibility(
              control,
              raw,
              fields: [],
              blocker: 'parent_published',
            ),
            control.family,
            control.identity,
            control.revision,
            raw,
          );
      await mount(t);
      expect(
        t
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('settings-change-body')),
            )
            .onChanged,
        isNull,
      );
      expect(find.textContaining('parent published'), findsOneWidget);
      expect(find.text('Check draft eligibility'), findsOneWidget);
      expect(api.updates, 0);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'draft changed while exact eligibility waits cannot open obsolete review',
    (t) async {
      await mount(t);
      await sectionDraft(t);
      final held = Completer<AdminSettingsEligibility>();
      AdminSettingsControl? captured;
      String? bytes;
      api.onEligibility = (control, raw) {
        captured = control;
        bytes = raw;
        return held.future;
      };
      await t.ensureVisible(find.text('Review change'));
      await t.tap(find.text('Review change'));
      await t.pump();
      // A programmatic controller change reproduces another draft source while the disabled editor waits.
      t
              .widget<TextField>(
                find.byKey(const ValueKey('settings-field-body')),
              )
              .controller!
              .text =
          'Changed during check';
      held.complete(
        AdminSettingsEligibility.parse(
          e.currentEligibility(
            captured!,
            bytes!,
            fields: [],
            blocker: 'patch_not_permitted',
          ),
          captured!.family,
          captured!.identity,
          captured!.revision,
          bytes!,
        ),
      );
      await t.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await t.pumpAndSettle();
      expect(find.text('Review setting change'), findsNothing);
      expect(find.textContaining('patch not permitted'), findsNothing);
      expect(api.updates, 0);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'replacement session during exact eligibility cannot restore editor or review',
    (t) async {
      await mount(t);
      await sectionDraft(t);
      final held = Completer<AdminSettingsEligibility>();
      AdminSettingsControl? captured;
      String? bytes;
      api.onEligibility = (control, raw) {
        captured = control;
        bytes = raw;
        return held.future;
      };
      await t.ensureVisible(find.text('Review change'));
      await t.tap(find.text('Review change'));
      await t.pump();
      await t.runAsync(() => auth.session(client, f.sessionB));
      await t.pump();
      held.complete(
        AdminSettingsEligibility.parse(
          e.currentEligibility(captured!, bytes!),
          captured!.family,
          captured!.identity,
          captured!.revision,
          bytes!,
        ),
      );
      await t.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await t.pumpAndSettle();
      expect(find.text('Review setting change'), findsNothing);
      expect(api.updates, 0);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'contextual60second eligibility expires review earlier than original90second request',
    (t) async {
      await mount(t);
      await sectionDraft(t);
      await click(t, find.text('Review change'));
      container.read(clock.notifier).state = f.at.add(
        const Duration(seconds: 60),
      );
      await t.pump(const Duration(seconds: 1));
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save original request'),
            )
            .onPressed,
        isNull,
      );
      expect(api.updates, 0);
      await click(t, find.text('Cancel'));
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'receipt policy narrow chooser selects French without changing enabled and saves exact original bytes',
    (t) async {
      api.current = e.languageControl();
      AdminSettingsPreparedUpdate? sent;
      api.onUpdate = (i) async {
        sent = i;
        return AdminSettingsReceipt.parse(f.receiptJson(i));
      };
      await mount(t, width: 390, scale: 1.3);
      await click(
        t,
        find.byKey(const ValueKey('settings-change-receipt_language')),
      );
      await click(
        t,
        find.byKey(const ValueKey('settings-field-receipt_language')),
      );
      await click(t, find.text('Français').last);
      await t.enterText(
        find.byKey(const Key('settings-reason')),
        'Use reviewed French receipt',
      );
      await click(t, find.text('Review change'));
      expect(find.textContaining('"receipt_language": "fr"'), findsOneWidget);
      await click(t, find.text('Save original request'));
      expect(sent!.patchJson, '{"receipt_language":"fr"}');
      expect(api.updates, 1);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'new receipt policy has no guessed language and explicit English selection creates review',
    (t) async {
      final original = e.languageControl();
      final raw = {
        'contract_version': 2,
        'scope': 'runtime_controls',
        'ok': true,
        'family': original.family.key,
        'identity': original.identity,
        'revision': 0,
        'exists': false,
        'value': null,
        'redacted': false,
        'content_sha256': null,
        'checked_at': settingsUtc(f.at),
        'sample_valid_until': settingsUtc(
          f.at.add(const Duration(seconds: 60)),
        ),
        'can_manage': true,
      };
      api.current = AdminSettingsControl.parse(
        raw,
        original.family,
        original.identity,
      );
      await mount(t);
      expect(
        t
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const ValueKey('settings-field-receipt_language')),
            )
            .initialValue,
        isNull,
      );
      await click(
        t,
        find.byKey(const ValueKey('settings-change-receipt_language')),
      );
      await click(
        t,
        find.byKey(const ValueKey('settings-field-receipt_language')),
      );
      await click(t, find.text('English').last);
      await t.enterText(
        find.byKey(const Key('settings-reason')),
        'Create reviewed English policy',
      );
      await click(t, find.text('Review change'));
      expect(find.textContaining('"receipt_language": "en"'), findsOneWidget);
      expect(t.takeException(), isNull);
      await click(t, find.text('Cancel'));
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'published document status-only capability and archived status set remain visible',
    (t) async {
      api.current = e.control('policy_documents', status: 'archived');
      api.onEligibility = (control, raw) async =>
          AdminSettingsEligibility.parse(
            e.currentEligibility(
              control,
              raw,
              fields: ['status'],
              statuses: ['archived'],
            ),
            control.family,
            control.identity,
            control.revision,
            raw,
          );
      await mount(t);
      expect(
        t
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('settings-change-title')),
            )
            .onChanged,
        isNull,
      );
      final statuses = t
          .widget<DropdownButton<String>>(
            find.descendant(
              of: find.byKey(const ValueKey('settings-field-status')),
              matching: find.byType(DropdownButton<String>),
            ),
          )
          .items!;
      expect(statuses.map((x) => x.value), ['archived']);
      expect(api.updates, 0);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'context reader loading failure and retry remain truthful without raw disclosure',
    (t) async {
      final held = Completer<AdminSettingsEligibility>();
      api.onEligibility = (_, _) => held.future;
      await mount(t);
      expect(find.text('Checking edit eligibility.'), findsOneWidget);
      expect(
        t
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('settings-change-body')),
            )
            .onChanged,
        isNull,
      );
      held.completeError(StateError('PRIVATE_ELIGIBILITY_CANARY'));
      await t.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await t.pumpAndSettle();
      expect(
        find.textContaining('Edit eligibility could not be verified.'),
        findsOneWidget,
      );
      expect(find.textContaining('PRIVATE_ELIGIBILITY_CANARY'), findsNothing);
      api.onEligibility = (control, raw) async =>
          AdminSettingsEligibility.parse(
            e.currentEligibility(control, raw),
            control.family,
            control.identity,
            control.revision,
            raw,
          );
      await click(t, find.text('Check draft eligibility'));
      expect(
        t
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('settings-change-body')),
            )
            .onChanged,
        isNotNull,
      );
      expect(
        find.textContaining('Edit eligibility could not be verified.'),
        findsNothing,
      );
      expect(api.updates, 0);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'new section prospective parent admits editable draft and full final draft is rechecked',
    (t) async {
      api.current = e.control('policy_document_sections', exists: false);
      final observed = <String>[];
      api.onEligibility = (control, raw) async {
        observed.add(raw);
        final patch = jsonDecode(raw) as Map;
        final hasParent = patch['policy_document_id'] == f.request;
        return AdminSettingsEligibility.parse(
          e.currentEligibility(
            control,
            raw,
            fields: hasParent ? null : [],
            blocker: hasParent ? null : 'parent_required',
          ),
          control.family,
          control.identity,
          control.revision,
          raw,
        );
      };
      await mount(t);
      expect(
        t
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('settings-change-body')),
            )
            .onChanged,
        isNull,
      );
      await click(
        t,
        find.byKey(const ValueKey('settings-change-policy_document_id')),
      );
      await t.enterText(
        find.byKey(const ValueKey('settings-field-policy_document_id')),
        f.request,
      );
      await click(t, find.text('Check draft eligibility'));
      for (final field in ['section_key', 'title', 'body']) {
        await click(t, find.byKey(ValueKey('settings-change-$field')));
        await t.enterText(
          find.byKey(ValueKey('settings-field-$field')),
          field == 'section_key'
              ? 'privacy'
              : field == 'title'
              ? 'Privacy'
              : 'Reviewed disclosure',
        );
      }
      await t.enterText(
        find.byKey(const Key('settings-reason')),
        'Create reviewed disclosure section',
      );
      await click(t, find.text('Review change'));
      expect((jsonDecode(observed.last) as Map).keys.toSet(), {
        'policy_document_id',
        'section_key',
        'title',
        'body',
      });
      expect(find.text('Review setting change'), findsOneWidget);
      expect(api.updates, 0);
      await click(t, find.text('Cancel'));
      await t.pumpWidget(const SizedBox());
    },
  );
}
