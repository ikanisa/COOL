import 'dart:async';
import 'dart:convert';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_governed_settings_models.dart';
import 'package:collect_app/admin/core/admin_governed_settings_sdk.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_action_session_test.dart' as auth;
import 'support/settings_fixture.dart' as f;
import 'support/settings_eligibility_fixture.dart' as e;

void main() {
  test(
    'all25 actual SQL13key eligibility observations parse exact discovery digest',
    () {
      for (final family in AdminSettingsFamily.values) {
        final raw = e.observedEligibility(family.key);
        final value = AdminSettingsEligibility.parse(
          raw,
          family,
          family.identity(raw['identity']),
          raw['revision'] as int,
          '{}',
        );
        expect(value.patchSha256, settingsHash('{}'));
        expect(value.sample.fresh(settingsInstant(raw['checked_at'])), isTrue);
      }
    },
  );
  test(
    'actual language250 closed catalog matches only rw/en/fr writable policy selection',
    () {
      final family = AdminSettingsFamily.parse('sms_receipt_policies'),
          raw = e.observedLanguageCatalog();
      final page = AdminSettingsCatalog.parse(raw, family, limit: 20);
      expect(family.writableFields, ['enabled', 'receipt_language']);
      expect(page.rows.single.value['receipt_language'], 'rw');
      for (final language in ['rw', 'en', 'fr']) {
        expect(family.patch({'receipt_language': language}), {
          'receipt_language': language,
        });
      }
      for (final language in ['RW', 'EN', 'xx', ' fr', 'fr\n', 'é', '', null]) {
        expect(
          () => family.patch({'receipt_language': language}),
          throwsFormatException,
        );
      }
      expect(
        () => AdminSettingsCatalog.parse(
          {
            ...raw,
            'language_options': ['rw', 'en', 'fr'],
          },
          family,
          limit: 20,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'fresh exact contextual draft permits supported section edit without immutable wiring',
    () {
      final control = e.control('policy_document_sections'),
          raw = jsonEncode({'body': 'Reviewed disclosure'});
      final eligible = AdminSettingsEligibility.parse(
        e.currentEligibility(control, raw),
        control.family,
        control.identity,
        control.revision,
        raw,
      );
      final prepared = AdminSettingsPreparedUpdate.prepare(
        requestId: f.request,
        control: control,
        patch: {'body': 'Reviewed disclosure'},
        reason: 'Review updated disclosure',
        now: f.at,
        scope: f.scope,
        eligibility: eligible,
      );
      expect(prepared.patchJson, raw);
      expect(
        prepared.current(f.scope, f.at.add(const Duration(seconds: 60))),
        isFalse,
      );
      expect(
        () => AdminSettingsPreparedUpdate.prepare(
          requestId: f.request,
          control: control,
          patch: {'body': 'Another body'},
          reason: 'Review updated disclosure',
          now: f.at,
          scope: f.scope,
          eligibility: eligible,
        ),
        throwsFormatException,
      );
      expect(
        () => eligible.validate(
          control,
          raw,
          f.at.add(const Duration(seconds: 60)),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'prospective new section requires matching actual parent eligibility before preparation',
    () {
      final control = e.control('policy_document_sections', exists: false),
          patch = {
            'policy_document_id': f.request,
            'section_key': 'privacy',
            'title': 'Privacy',
            'body': 'Reviewed disclosure',
          };
      final raw = jsonEncode(patch);
      final denied = AdminSettingsEligibility.parse(
        e.currentEligibility(
          control,
          raw,
          fields: [],
          blocker: 'parent_required',
        ),
        control.family,
        control.identity,
        0,
        raw,
      );
      expect(
        () => AdminSettingsPreparedUpdate.prepare(
          requestId: f.request,
          control: control,
          patch: patch,
          reason: 'Create reviewed disclosure',
          now: f.at,
          scope: f.scope,
          eligibility: denied,
        ),
        throwsFormatException,
      );
      final admitted = AdminSettingsEligibility.parse(
        e.currentEligibility(control, raw),
        control.family,
        control.identity,
        0,
        raw,
      );
      expect(
        AdminSettingsPreparedUpdate.prepare(
          requestId: f.request,
          control: control,
          patch: patch,
          reason: 'Create reviewed disclosure',
          now: f.at,
          scope: f.scope,
          eligibility: admitted,
        ).expectedRevision,
        0,
      );
    },
  );
  test(
    'publication uses current backend status set and blocker while archived cannot unarchive',
    () {
      for (final family in [
        'policy_documents',
        'notification_template_versions',
      ]) {
        final control = e.control(family), raw = '{"status":"published"}';
        final ok = AdminSettingsEligibility.parse(
          e.currentEligibility(control, raw),
          control.family,
          control.identity,
          1,
          raw,
        );
        expect(
          AdminSettingsPreparedUpdate.prepare(
            requestId: f.request,
            control: control,
            patch: {'status': 'published'},
            reason: 'Publish reviewed document',
            now: f.at,
            scope: f.scope,
            eligibility: ok,
          ).patchJson,
          raw,
        );
        final blocked = AdminSettingsEligibility.parse(
          e.currentEligibility(
            control,
            raw,
            statuses: ['draft', 'archived'],
            blocker: 'sections_required',
          ),
          control.family,
          control.identity,
          1,
          raw,
        );
        expect(
          () => blocked.validate(control, raw, f.at),
          throwsFormatException,
        );
        final archived = e.control(family, status: 'archived');
        final cannotResume = AdminSettingsEligibility.parse(
          e.currentEligibility(
            archived,
            raw,
            fields: ['status'],
            statuses: ['archived'],
            blocker: 'status_not_permitted',
          ),
          archived.family,
          archived.identity,
          1,
          raw,
        );
        expect(
          () => cannotResume.validate(archived, raw, f.at),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'eligibility refuses extra disclosure wrong family identity revision digest status and capability',
    () {
      final control = e.control('policy_documents'),
          raw = '{"title":"Reviewed"}',
          value = e.currentEligibility(control, raw);
      for (final patch in [
        {'session_id': f.sessionA},
        {'family': 'brand_entities'},
        {
          'identity': {'id': '99850000-0000-4000-8000-000000000002'},
        },
        {'revision': 2},
        {'patch_sha256': settingsHash('$raw ')},
        {
          'permitted_fields': ['raw_reason'],
        },
        {
          'permitted_statuses': ['live'],
        },
        {'blocker': 'unknown'},
        {'can_manage': false},
      ]) {
        expect(
          () => AdminSettingsEligibility.parse(
            {...value, ...patch},
            control.family,
            control.identity,
            1,
            raw,
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'actual pinned SDK forwards raw UTF8 prospective draft and exact13key result under bearer',
    () async {
      final control = e.control('policy_document_sections'),
          raw = ' {"body":"Reviewed α"} ';
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://synthetic.invalid',
        'synthetic-publishable',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((r) async {
          if (r.url.path.endsWith('/verify')) {
            final v = (jsonDecode(r.body)['token'] as String).split('|');
            return auth.response(auth.authReceipt(v[0], v[1]));
          }
          requests.add(r);
          return auth.response(e.currentEligibility(control, raw));
        }),
      );
      try {
        await auth.session(client, f.sessionA);
        final repository = AdminRepository(client, isCurrent: () => true);
        final sdk = AdminGovernedSettingsSdk(
          rpc: (n, p) => repository.rpcMap(n, params: p, automaticRetry: false),
          isCurrent: () => true,
          now: () => f.at,
          currentSession: () => adminSessionKey(client.auth.currentSession),
        );
        expect(
          (await sdk.eligibility(control, raw)).patchSha256,
          settingsHash(raw),
        );
        expect(
          requests.single.url.path.split('/').last,
          'admin_get_runtime_control_eligibility_v1',
        );
        expect(requests.single.headers['Authorization'], startsWith('Bearer '));
        expect(jsonDecode(requests.single.body), {
          'p_family': control.family.key,
          'p_identity': control.identity,
          'p_expected_revision': 1,
          'p_patch_json': raw,
        });
      } finally {
        await client.dispose();
      }
    },
  );
  test(
    'late eligibility rejects changed session authority and expired sampled response',
    () async {
      final control = e.control('policy_documents'),
          held = Completer<Object?>();
      var current = true;
      final sdk = AdminGovernedSettingsSdk(
        rpc: (_, _) => held.future,
        isCurrent: () => current,
        now: () => f.at,
        currentSession: () => f.scope.key,
      );
      final result = sdk.eligibility(control, '{}');
      current = false;
      held.complete(e.currentEligibility(control, '{}'));
      await expectLater(result, throwsA(isA<AdminSessionChanged>()));
      final stale = AdminGovernedSettingsSdk(
        rpc: (_, _) async => e.currentEligibility(
          control,
          '{}',
          at: f.at.subtract(const Duration(minutes: 2)),
        ),
        isCurrent: () => true,
        now: () => f.at,
        currentSession: () => f.scope.key,
      );
      await expectLater(
        stale.eligibility(control, '{}'),
        throwsFormatException,
      );
    },
  );
  test(
    'eligible intent expiry denies mutation before transport even when90second original remains',
    () async {
      final control = e.control('policy_documents'),
          raw = '{"title":"Reviewed"}';
      final eligible = AdminSettingsEligibility.parse(
        e.currentEligibility(control, raw),
        control.family,
        control.identity,
        1,
        raw,
      );
      final prepared = AdminSettingsPreparedUpdate.prepare(
        requestId: f.request,
        control: control,
        patch: {'title': 'Reviewed'},
        reason: 'Review updated policy',
        now: f.at,
        scope: f.scope,
        eligibility: eligible,
      );
      var calls = 0;
      final sdk = AdminGovernedSettingsSdk(
        rpc: (_, _) async {
          calls++;
          return f.receiptJson(prepared);
        },
        isCurrent: () => true,
        now: () => f.at.add(const Duration(seconds: 60)),
        currentSession: () => f.scope.key,
      );
      await expectLater(sdk.update(prepared), throwsFormatException);
      expect(calls, 0);
    },
  );
}
