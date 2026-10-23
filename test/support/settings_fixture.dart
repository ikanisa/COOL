import 'dart:convert';
import 'dart:io';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_governed_settings_models.dart';
import 'package:collect_app/admin/core/admin_governed_settings_checkpoint.dart';
import 'package:collect_app/admin/core/admin_governed_settings_sdk.dart';

const actor = '99430000-0000-4000-8000-000000000001';
const sessionA = '99430000-0000-4000-8000-000000010001';
const sessionB = '99430000-0000-4000-8000-000000010002';
const request = '99850000-0000-4000-8000-000000000001';
final at = DateTime.utc(2026, 10, 1, 17, 17, 36);
const scope = (key: (userId: actor, sessionId: sessionA), generation: 1);
final family = AdminSettingsFamily.parse('account_request_reason_options');
final identity = family.identity({
  'request_type': 'account_deletion',
  'locale': 'en',
  'key': 'qa_runtime_current',
});
Map<String, dynamic> observed(String kind) => Map<String, dynamic>.from(
  jsonDecode(
        File('test/fixtures/observed_runtime_v2.json').readAsStringSync(),
      )['observations'][kind]['data']
      as Map,
);
Map<String, dynamic> clone(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
Map<String, dynamic> controlJson({
  bool stale = false,
  bool redacted = false,
  bool canManage = true,
}) {
  final v = observed('control');
  v['checked_at'] = settingsUtc(
    stale ? at.subtract(const Duration(minutes: 2)) : at,
  );
  v['sample_valid_until'] = settingsUtc(
    (stale ? at.subtract(const Duration(minutes: 2)) : at).add(
      const Duration(seconds: 60),
    ),
  );
  v['can_manage'] = canManage;
  if (redacted) {
    v['redacted'] = true;
    v['content_sha256'] = null;
  }
  return v;
}

AdminSettingsControl control() =>
    AdminSettingsControl.parse(controlJson(), family, identity);
AdminSettingsPreparedUpdate intent({
  String id = request,
  AdminSessionScope session = scope,
  DateTime? now,
}) => AdminSettingsPreparedUpdate.prepare(
  requestId: id,
  control: control(),
  patch: {'label': 'Updated accountable reason'},
  reason: 'Synthetic accountable runtime edit',
  now: now ?? at,
  scope: session,
);
Map<String, dynamic> receiptJson(
  AdminSettingsPreparedUpdate i, {
  bool changed = true,
}) => {
  'contract_version': 2,
  'scope': 'runtime_controls',
  'request_id': i.requestId,
  'request_fingerprint': i.fingerprint,
  'family': i.family.key,
  'identity': i.identity,
  'previous_revision': i.expectedRevision,
  'revision': i.expectedRevision + (changed ? 1 : 0),
  'changed': changed,
  'updated_at': settingsUtc(
    changed ? i.createdAt : i.createdAt.subtract(const Duration(days: 1)),
  ),
  'content_sha256': 'a' * 64,
  'recorded_at': settingsUtc(i.createdAt),
  'expires_at': settingsUtc(i.expiresAt),
};
Map<String, dynamic> lookupJson(
  AdminSettingsBookmark b,
  DateTime clock, {
  String status = 'recorded',
  AdminSettingsReceipt? receipt,
}) => {
  'contract_version': 2,
  'scope': 'runtime_controls',
  'request_id': b.requestId,
  'request_fingerprint': b.fingerprint,
  'family': b.family.key,
  'identity': b.identity,
  'expires_at': settingsUtc(b.expiresAt),
  'checked_at': settingsUtc(clock),
  'sample_valid_until': settingsUtc(clock.add(const Duration(seconds: 60))),
  'status': status,
  'receipt': status == 'recorded' ? receiptJson(intent(id: b.requestId)) : null,
};

class MemorySettingsStore implements AdminSettingsCheckpointStore {
  final originals = <String, String>{}, resolutions = <String, String>{};
  bool failRead = false,
      failWrite = false,
      dropWrite = false,
      failResolve = false;
  void Function()? onWrite;
  @override
  List<String> read(String owner) {
    if (failRead) throw StateError('PRIVATE_STORAGE_CANARY');
    return originals.entries
        .where((e) => !resolutions.containsKey(e.key))
        .map((e) => e.value)
        .toList();
  }

  Future<void> _tail = Future.value();
  Future<void> _exclusive(void Function() work) {
    final next = _tail.then((_) => work());
    _tail = next.catchError((_) {});
    return next;
  }

  @override
  Future<void> write(AdminSettingsBookmark b) => _exclusive(() {
    if (failWrite) throw StateError('PRIVATE_STORAGE_CANARY');
    if (read(b.ownerDigest).isNotEmpty) {
      throw const AdminSettingsPendingOriginal();
    }
    if (originals.containsKey(b.requestId)) {
      throw StateError('original duplicate');
    }
    if (!dropWrite) originals[b.requestId] = b.encode();
    onWrite?.call();
  });
  @override
  Future<void> resolve(AdminSettingsBookmark b, String status) =>
      _exclusive(() {
        if (failResolve) throw StateError('PRIVATE_STORAGE_CANARY');
        if (originals[b.requestId] != b.encode()) {
          throw StateError('original mismatch');
        }
        resolutions[b.requestId] = status;
      });
}

class SettingsApiFake implements AdminGovernedSettingsApi {
  Future<AdminSettingsReceipt> Function(AdminSettingsPreparedUpdate)? onUpdate;
  Future<AdminSettingsLookup> Function(AdminSettingsBookmark)? onLookup;
  Future<AdminSettingsHistory> Function(
    AdminSettingsFamily,
    Map<String, Object?>,
    int,
    AdminSettingsHistoryCursor?,
  )?
  onHistory;
  Future<AdminSettingsEligibility> Function(AdminSettingsControl, String)?
  onEligibility;
  int eligibilityReads = 0;
  @override
  Future<AdminSettingsEligibility> eligibility(
    AdminSettingsControl control,
    String patch,
  ) async {
    eligibilityReads++;
    if (onEligibility != null) return onEligibility!(control, patch);
    return AdminSettingsEligibility.parse(
      {
        'contract_version': 1,
        'scope': 'runtime_control_eligibility',
        'family': control.family.key,
        'identity': control.identity,
        'revision': control.revision,
        'patch_sha256': settingsHash(patch),
        'checked_at': settingsUtc(at),
        'sample_valid_until': settingsUtc(at.add(const Duration(seconds: 60))),
        'can_manage': true,
        'permitted_fields': control.family.writableFields
            .where(
              (f) =>
                  !control.exists ||
                  !control.family.immutableFields.contains(f),
            )
            .toList(),
        'permitted_statuses':
            const {
              'policy_documents',
              'notification_template_versions',
            }.contains(control.family.key)
            ? ['draft', 'published', 'archived']
            : [],
        'create_allowed': control.family.createAllowed,
        'blocker': null,
      },
      control.family,
      control.identity,
      control.revision,
      patch,
    );
  }

  int updates = 0, lookups = 0;
  @override
  Future<AdminSettingsReceipt> update(AdminSettingsPreparedUpdate i) {
    updates++;
    return onUpdate?.call(i) ??
        Future.value(AdminSettingsReceipt.parse(receiptJson(i)));
  }

  @override
  Future<AdminSettingsLookup> lookup(AdminSettingsBookmark b) {
    lookups++;
    return onLookup?.call(b) ??
        Future.value(AdminSettingsLookup.parse(lookupJson(b, at), b));
  }

  @override
  Future<AdminSettingsCatalog> catalog(
    AdminSettingsFamily f, {
    int limit = 25,
    Map<String, Object?>? after,
  }) async {
    final v = observed('catalog');
    v['limit'] = limit;
    v['checked_at'] = settingsUtc(at);
    v['sample_valid_until'] = settingsUtc(at.add(const Duration(seconds: 60)));
    return AdminSettingsCatalog.parse(v, f, limit: limit);
  }

  @override
  Future<AdminSettingsControl> control(
    AdminSettingsFamily f,
    Map<String, Object?> identity,
  ) async => AdminSettingsControl.parse(controlJson(), f, identity);
  @override
  Future<AdminSettingsHistory> history(
    AdminSettingsFamily f,
    Map<String, Object?> identity, {
    int limit = 20,
    AdminSettingsHistoryCursor? before,
  }) async {
    if (onHistory != null) return onHistory!(f, identity, limit, before);
    final v = observed('history');
    v['limit'] = limit;
    return AdminSettingsHistory.parse(
      v,
      f,
      identity,
      limit: limit,
      before: before,
    );
  }
}
