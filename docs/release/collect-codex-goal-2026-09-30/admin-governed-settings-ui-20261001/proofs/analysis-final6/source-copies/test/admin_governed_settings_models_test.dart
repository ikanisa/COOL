import 'dart:convert';
import 'package:collect_app/admin/core/admin_governed_settings_models.dart';
import 'package:collect_app/admin/core/admin_governed_settings_checkpoint.dart';
import 'package:collect_app/admin/core/admin_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/settings_fixture.dart' as f;

void main() {
  test(
    'all five actual SQL observed DTOs parse with composite key order and nullable owner actor',
    () {
      final catalog = AdminSettingsCatalog.parse(
        f.observed('catalog'),
        f.family,
        limit: 25,
      );
      expect(catalog.rows.single.identity.keys, [
        'request_type',
        'locale',
        'key',
      ]);
      final control = AdminSettingsControl.parse(
        f.observed('control'),
        f.family,
        f.identity,
      );
      expect(control.revision, 1);
      final receipt = AdminSettingsReceipt.parse(f.observed('receipt'));
      final raw = jsonEncode({
        'version': 2,
        'owner_digest': adminSettingsOwnerDigest(f.actor),
        'request_id': receipt.requestId,
        'family': receipt.family.key,
        'identity': receipt.identity,
        'request_fingerprint': receipt.fingerprint,
        'expires_at': settingsUtc(receipt.expiresAt),
      });
      final bookmark = AdminSettingsBookmark.parse(
        raw,
        adminSettingsOwnerDigest(f.actor),
      );
      expect(
        AdminSettingsLookup.parse(
          f.observed('lookup'),
          bookmark,
        ).receipt!.fingerprint,
        receipt.fingerprint,
      );
      final history = AdminSettingsHistory.parse(
        f.observed('history'),
        f.family,
        f.identity,
        limit: 25,
      );
      expect(history.events.last.actorId, isNull);
      expect(history.events.last.requestId, isNull);
    },
  );
  test(
    'actual SQL original request fingerprint equals client scalar LF grammar',
    () {
      final receipt = AdminSettingsReceipt.parse(f.observed('receipt'));
      final now = receipt.expiresAt.subtract(const Duration(seconds: 90));
      final prepared = AdminSettingsPreparedUpdate.prepare(
        requestId: receipt.requestId,
        control: AdminSettingsControl.parse(
          f.observed('control'),
          f.family,
          f.identity,
        ),
        patch: {'label': 'Updated synthetic label'},
        reason: 'Synthetic accountable runtime edit',
        now: now,
        scope: f.scope,
      );
      expect(prepared.fingerprint, receipt.fingerprint);
      expect(prepared.patchJson, '{"label":"Updated synthetic label"}');
      receipt.validatePrepared(prepared);
    },
  );
  test(
    'all 25 reviewed families descriptors are closed and preference catalog is excluded',
    () {
      expect(AdminSettingsFamily.values.length, 25);
      expect(
        () => AdminSettingsFamily.parse('notification_preferences'),
        throwsFormatException,
      );
      for (final family in AdminSettingsFamily.values) {
        final descriptor = {
          'identity_fields': family.identityFields,
          'writable_fields': family.writableFields,
          'immutable_fields': family.immutableFields,
          'nullable_fields': family.nullableFields,
          'field_types': family.fieldTypes,
          'create_allowed': family.createAllowed,
          'can_manage': false,
        };
        expect(
          AdminSettingsDescriptor.parse(descriptor, family).canManage,
          isFalse,
        );
        expect(
          () => AdminSettingsDescriptor.parse({
            ...descriptor,
            'relation': 'private',
          }, family),
          throwsFormatException,
        );
        expect(
          () => family.identity({
            for (final k in family.identityFields)
              k: family.fieldTypes[k] == 'boolean'
                  ? false
                  : family.fieldTypes[k] == 'uuid'
                  ? 'ABCDEF00-0000-4000-8000-000000000001'
                  : 'valid',
          }),
          family.identityFields.any((k) => family.fieldTypes[k] != 'text')
              ? throwsFormatException
              : returnsNormally,
        );
      }
    },
  );
  test('closed DTOs reject disclosure additions and incorrect redaction', () {
    expect(
      () => AdminSettingsControl.parse(
        {...f.controlJson(), 'session_id': f.sessionA},
        f.family,
        f.identity,
      ),
      throwsFormatException,
    );
    expect(
      () => AdminSettingsControl.parse(
        {...f.controlJson(), 'redacted': true},
        f.family,
        f.identity,
      ),
      throwsFormatException,
    );
    expect(
      () => AdminSettingsHistory.parse(
        {...f.observed('history'), 'history_complete': true},
        f.family,
        f.identity,
        limit: 25,
      ),
      throwsFormatException,
    );
    final h = f.observed('history');
    (h['rows'] as List).first['reason'] = 'raw reason';
    expect(
      () => AdminSettingsHistory.parse(h, f.family, f.identity, limit: 25),
      throwsFormatException,
    );
  });
  test(
    'nullable typed patch rejects invalid scalar, unsafe JSON, overflow and malformed dates',
    () {
      expect(f.family.patch({'description': null}), {'description': null});
      for (final patch in [
        {'enabled': 'true'},
        {'display_order': 1.0},
        {'display_order': 10001},
        {'label': null},
        {
          'metadata': {'access_token': 'private'},
        },
        {
          'metadata': {'1bad': 1},
        },
        {
          'metadata': {'safe': 100000000001},
        },
      ]) {
        expect(() => f.family.patch(patch), throwsFormatException);
      }
      final policy = AdminSettingsFamily.parse('policy_documents');
      expect(
        () => policy.patch({'effective_at': '2026-02-30T00:00:00Z'}),
        throwsFormatException,
      );
      expect(
        () => policy.patch({'effective_at': '2026-10-01 12:00:00'}),
        throwsFormatException,
      );
      expect(
        () => settingsInstant('2026-10-01T17:17:36Z'),
        throwsFormatException,
      );
    },
  );
  test('immutable publication and wiring cannot enter a prepared update', () {
    final family = AdminSettingsFamily.parse('notification_template_versions');
    final raw = {
      'contract_version': 2,
      'scope': 'runtime_controls',
      'ok': true,
      'family': family.key,
      'identity': {'id': f.request},
      'revision': 1,
      'exists': true,
      'value': {
        'id': f.request,
        'template_key': 'notice',
        'version': 'v1',
        'status': 'published',
        'title_template': 'Published title',
        'body_template': 'Published body',
        'effective_at': '2026-10-01T00:00:00Z',
        'metadata': {},
      },
      'redacted': false,
      'content_sha256': 'a' * 64,
      'checked_at': settingsUtc(f.at),
      'sample_valid_until': settingsUtc(f.at.add(const Duration(seconds: 60))),
      'can_manage': true,
    };
    final control = AdminSettingsControl.parse(raw, family, {'id': f.request});
    for (final patch in [
      {'title_template': 'Changed title'},
      {'template_key': 'another'},
    ]) {
      expect(
        () => AdminSettingsPreparedUpdate.prepare(
          requestId: f.request,
          control: control,
          patch: patch,
          reason: 'Accountable policy review',
          now: f.at,
          scope: f.scope,
        ),
        throwsFormatException,
      );
    }
  });
  test(
    'prepared bytes are immutable, Unicode trim exact, deadline and replacement scope deny',
    () {
      final patch = {'label': 'Café 🧾'};
      final prepared = AdminSettingsPreparedUpdate.prepare(
        requestId: f.request,
        control: f.control(),
        patch: patch,
        reason: '\ufeff　Reason 🧾 review　\ufeff',
        now: f.at,
        scope: f.scope,
      );
      patch['label'] = 'replaced';
      expect(prepared.patchJson, '{"label":"Café 🧾"}');
      expect(prepared.reason, 'Reason 🧾 review');
      expect(
        () => prepared.parameters['p_reason'] = 'changed',
        throwsUnsupportedError,
      );
      expect(
        prepared.current((key: f.scope.key, generation: 2), f.at),
        isFalse,
      );
      expect(prepared.current(f.scope, prepared.expiresAt), isFalse);
      expect(
        () => AdminSettingsPreparedUpdate.prepare(
          requestId: f.request,
          control: f.control(),
          patch: {'label': 'Valid'},
          reason: 'Valid accountable reason',
          now: f.at,
          scope: f.scope,
          lifetime: const Duration(seconds: 121),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'bookmarks contain only lookup metadata and reject foreign owner/replay fields',
    () {
      final owner = adminSettingsOwnerDigest(f.actor),
          bookmark = AdminSettingsBookmark.fromPrepared(
            adminSettingsOwnerDigest(f.actor),
            f.intent(),
          );
      final decoded = jsonDecode(bookmark.encode()) as Map;
      expect(decoded.keys.toSet(), {
        'version',
        'owner_digest',
        'request_id',
        'family',
        'identity',
        'request_fingerprint',
        'expires_at',
      });
      expect(bookmark.parameters.keys.toSet(), {
        'p_request_id',
        'p_family',
        'p_identity',
        'p_request_fingerprint',
        'p_expires_at',
      });
      expect(
        () => AdminSettingsBookmark.parse(
          jsonEncode({...decoded, 'patch_json': '{}'}),
          owner,
        ),
        throwsFormatException,
      );
      expect(
        () => AdminSettingsBookmark.parse(bookmark.encode(), 'b' * 64),
        throwsFormatException,
      );
    },
  );
  test(
    'no-op receipts preserve old head timestamp without inventing change revision',
    () {
      final prepared = f.intent();
      final receipt = AdminSettingsReceipt.parse(
        f.receiptJson(prepared, changed: false),
      );
      receipt.validatePrepared(prepared);
      expect(receipt.updatedAt.isBefore(receipt.recordedAt), isTrue);
      expect(receipt.previousRevision, receipt.revision);
      expect(
        () => AdminSettingsReceipt.parse({
          ...f.receiptJson(prepared),
          'revision': prepared.expectedRevision,
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'history cursor tie ordering and original lookup bindings are immutable',
    () {
      final h = f.observed('history');
      final events = h['rows'] as List;
      events[1]['recorded_at'] = events[0]['recorded_at'];
      events[0]['event_id'] = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
      events[1]['event_id'] = '00000000-0000-4000-8000-000000000000';
      h['limit'] = 2;
      h['next_cursor'] = {
        'recorded_at': events.last['recorded_at'],
        'event_id': events.last['event_id'],
      };
      expect(
        AdminSettingsHistory.parse(
          h,
          f.family,
          f.identity,
          limit: 2,
        ).nextCursor,
        isNotNull,
      );
      expect(
        () => AdminSettingsHistory.parse(
          h,
          f.family,
          f.identity,
          limit: 2,
          before: AdminSettingsHistoryCursor(
            settingsInstant(events.first['recorded_at']),
            events.first['event_id'] as String,
          ),
        ),
        throwsFormatException,
      );
      final b = AdminSettingsBookmark.fromPrepared(
        adminSettingsOwnerDigest(f.actor),
        f.intent(),
      );
      expect(
        () => AdminSettingsLookup.parse({
          ...f.lookupJson(b, f.at),
          'request_fingerprint': 'b' * 64,
        }, b),
        throwsFormatException,
      );
    },
  );
  test(
    'family manage requires additional capability and audit permission is independent',
    () {
      const owner = AdminIdentity(
        userId: f.actor,
        displayName: 'Owner',
        roles: ['platform_owner'],
        permissions: ['settings.read', 'settings.manage', 'audit.read'],
      );
      final otp = AdminSettingsFamily.parse('otp_policy');
      expect(otp.canManage(owner), isFalse);
      expect(otp.canAudit(owner), isTrue);
      const auditOnly = AdminIdentity(
        userId: f.actor,
        displayName: 'Auditor',
        roles: ['platform_owner'],
        permissions: ['audit.read'],
      );
      expect(f.family.canRead(auditOnly), isFalse);
      expect(f.family.canAudit(auditOnly), isTrue);
    },
  );
  test(
    'lookup cannot settle from a receipt recorded after its fresh observation',
    () {
      final b = AdminSettingsBookmark.fromPrepared(
        adminSettingsOwnerDigest(f.actor),
        f.intent(),
      );
      expect(
        () => AdminSettingsLookup.parse(
          f.lookupJson(b, f.at.subtract(const Duration(seconds: 1))),
          b,
        ),
        throwsFormatException,
      );
    },
  );
}
