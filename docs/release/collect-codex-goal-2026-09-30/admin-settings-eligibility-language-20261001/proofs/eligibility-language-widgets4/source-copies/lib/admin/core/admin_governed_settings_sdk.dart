import 'dart:convert';
import 'admin_auth_guard.dart';
import 'admin_governed_settings_models.dart';
import 'admin_governed_settings_checkpoint.dart';

typedef AdminSettingsRpc =
    Future<Object?> Function(String name, Map<String, dynamic> parameters);

abstract interface class AdminGovernedSettingsApi {
  Future<AdminSettingsCatalog> catalog(
    AdminSettingsFamily family, {
    int limit = 25,
    Map<String, Object?>? after,
  });
  Future<AdminSettingsControl> control(
    AdminSettingsFamily family,
    Map<String, Object?> identity,
  );
  Future<AdminSettingsEligibility> eligibility(
    AdminSettingsControl control,
    String patchJson,
  );
  Future<AdminSettingsReceipt> update(AdminSettingsPreparedUpdate intent);
  Future<AdminSettingsLookup> lookup(AdminSettingsBookmark original);
  Future<AdminSettingsHistory> history(
    AdminSettingsFamily family,
    Map<String, Object?> identity, {
    int limit = 20,
    AdminSettingsHistoryCursor? before,
  });
}

/// The production callback uses AdminRepository.rpcMap with automaticRetry=false
/// and its sticky per-request SDK session fence. Typed reads are also validated
/// after awaits; a stale response never becomes current control authority.
class AdminGovernedSettingsSdk implements AdminGovernedSettingsApi {
  const AdminGovernedSettingsSdk({
    required this.rpc,
    required this.isCurrent,
    required this.now,
    required this.currentSession,
  });
  final AdminSettingsRpc rpc;
  final bool Function() isCurrent;
  final DateTime Function() now;
  final AdminSessionKey? Function() currentSession;
  void _current() {
    if (!isCurrent()) throw const AdminSessionChanged();
  }

  Future<Object?> _call(String name, Map<String, dynamic> parameters) async {
    _current();
    try {
      final value = await rpc(
        name,
        Map.unmodifiable(parameters),
      ).timeout(const Duration(seconds: 15));
      _current();
      return value;
    } catch (_) {
      _current();
      rethrow;
    }
  }

  @override
  Future<AdminSettingsCatalog> catalog(
    AdminSettingsFamily family, {
    int limit = 25,
    Map<String, Object?>? after,
  }) async {
    if (limit < 1 || limit > 25) governedSettingsInvalid('page size');
    final value = await _call('admin_list_runtime_controls_v2', {
      'p_family': family.key,
      'p_limit': limit,
      'p_after_identity': after == null ? null : family.identity(after),
    });
    final page = AdminSettingsCatalog.parse(value, family, limit: limit);
    if (!page.sample.fresh(now())) governedSettingsInvalid('expired catalog');
    return page;
  }

  @override
  Future<AdminSettingsControl> control(
    AdminSettingsFamily family,
    Map<String, Object?> identity,
  ) async {
    final bound = family.identity(identity);
    final value = await _call('admin_get_runtime_control_v2', {
      'p_family': family.key,
      'p_identity': bound,
    });
    final control = AdminSettingsControl.parse(value, family, bound);
    if (!control.sample!.fresh(now())) {
      governedSettingsInvalid('expired control');
    }
    return control;
  }

  @override
  Future<AdminSettingsEligibility> eligibility(
    AdminSettingsControl control,
    String patchJson,
  ) async {
    if (utf8.encode(patchJson).length > 65536)
      governedSettingsInvalid('eligibility patch');
    final value = await _call('admin_get_runtime_control_eligibility_v1', {
      'p_family': control.family.key,
      'p_identity': control.identity,
      'p_expected_revision': control.revision,
      'p_patch_json': patchJson,
    });
    final result = AdminSettingsEligibility.parse(
      value,
      control.family,
      control.identity,
      control.revision,
      patchJson,
    );
    if (!result.sample.fresh(now()))
      governedSettingsInvalid('expired eligibility');
    return result;
  }

  @override
  Future<AdminSettingsReceipt> update(
    AdminSettingsPreparedUpdate intent,
  ) async {
    if (intent.scope.key != currentSession()) throw const AdminSessionChanged();
    if (!now().toUtc().isBefore(intent.expiresAt) ||
        intent.eligibilityValidUntil != null &&
            !now().toUtc().isBefore(intent.eligibilityValidUntil!)) {
      governedSettingsInvalid('expired original request');
    }
    final value = await _call(
      'admin_update_runtime_control_v2',
      intent.parameters,
    );
    final receipt = AdminSettingsReceipt.parse(value);
    receipt.validatePrepared(intent);
    if (receipt.recordedAt.isAfter(now().add(const Duration(seconds: 5)))) {
      governedSettingsInvalid('receipt time');
    }
    return receipt;
  }

  @override
  Future<AdminSettingsLookup> lookup(AdminSettingsBookmark original) async {
    final actor = currentSession()?.userId;
    if (actor == null) {
      throw const AdminSessionChanged();
    }
    if (original.ownerDigest != adminSettingsOwnerDigest(actor)) {
      governedSettingsInvalid('original operator');
    }
    final value = await _call(
      'admin_get_runtime_control_request_v2',
      original.parameters,
    );
    final lookup = AdminSettingsLookup.parse(value, original);
    if (!lookup.sample.fresh(now())) governedSettingsInvalid('expired lookup');
    return lookup;
  }

  @override
  Future<AdminSettingsHistory> history(
    AdminSettingsFamily family,
    Map<String, Object?> identity, {
    int limit = 20,
    AdminSettingsHistoryCursor? before,
  }) async {
    if (limit < 1 || limit > 25) governedSettingsInvalid('page size');
    final bound = family.identity(identity);
    final value = await _call('admin_list_runtime_control_history_v2', {
      'p_family': family.key,
      'p_identity': bound,
      'p_limit': limit,
      'p_before_at': before == null ? null : settingsUtc(before.recordedAt),
      'p_before_event_id': before?.eventId,
    });
    final page = AdminSettingsHistory.parse(
      value,
      family,
      bound,
      limit: limit,
      before: before,
    );
    if (!page.sample.fresh(now())) governedSettingsInvalid('expired history');
    return page;
  }
}
