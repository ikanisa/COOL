import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'admin_auth_guard.dart';
import 'admin_governed_settings_models.dart';
import 'admin_governed_settings_sdk.dart';
import 'admin_governed_settings_checkpoint.dart';

class AdminSettingsActionState {
  const AdminSettingsActionState({
    this.pending = const [],
    this.busy = false,
    this.storageBlocked = false,
    this.message,
    this.receipt,
  });
  final List<AdminSettingsBookmark> pending;
  final bool busy, storageBlocked;
  final String? message;
  final AdminSettingsReceipt? receipt;
}

class AdminSettingsActionController
    extends StateNotifier<AdminSettingsActionState> {
  AdminSettingsActionController({
    required this.ownerDigest,
    required this.store,
    required this.api,
    required this.now,
    required this.scope,
    required this.canManage,
    required this.isCurrent,
  }) : super(const AdminSettingsActionState()) {
    reload();
  }
  final String ownerDigest;
  final AdminSettingsCheckpointStore? store;
  final AdminGovernedSettingsApi api;
  final DateTime Function() now;
  final AdminSessionScope? Function() scope;
  final bool Function(AdminSettingsFamily) canManage;
  final bool Function() isCurrent;
  bool _departed = false;
  bool get _current => !_departed && isCurrent();
  @override
  void dispose() {
    _departed = true;
    super.dispose();
  }

  void reload() {
    if (!_current || state.busy) return;
    try {
      if (store == null) governedSettingsInvalid('recovery storage');
      final raw = store!.read(ownerDigest);
      if (raw.length > 50) governedSettingsInvalid('pending request limit');
      final pending = raw
          .map((x) => AdminSettingsBookmark.parse(x, ownerDigest))
          .toList();
      if (pending.map((x) => x.requestId).toSet().length != pending.length) {
        governedSettingsInvalid('duplicate bookmark');
      }
      state = AdminSettingsActionState(
        pending: List.unmodifiable(pending),
        message: state.message,
        receipt: state.receipt,
      );
    } catch (_) {
      state = AdminSettingsActionState(
        pending: state.pending,
        storageBlocked: true,
        message:
            'Recovery storage is unavailable. Restore storage before saving a setting.',
      );
    }
  }

  Future<void> submit(AdminSettingsPreparedUpdate intent) async {
    if (!_current ||
        state.busy ||
        state.storageBlocked ||
        state.pending.isNotEmpty ||
        !canManage(intent.family) ||
        !intent.current(scope(), now())) {
      return;
    }
    final original = AdminSettingsBookmark.fromPrepared(ownerDigest, intent);
    final pending = List<AdminSettingsBookmark>.unmodifiable([
      ...state.pending,
      original,
    ]);
    state = AdminSettingsActionState(pending: state.pending, busy: true);
    try {
      if (store == null) governedSettingsInvalid('recovery storage');
      await store!.write(original);
      final retained = store!.read(ownerDigest);
      if (retained.length != 1 || retained.single != original.encode()) {
        governedSettingsInvalid('bookmark acknowledgement');
      }
    } on AdminSettingsPendingOriginal {
      if (_current) {
        state = const AdminSettingsActionState(
          message:
              'Another original request needs investigation before a new change.',
        );
        reload();
      }
      return;
    } catch (_) {
      if (_current) {
        state = AdminSettingsActionState(
          pending: pending,
          storageBlocked: true,
          message:
              'The recovery bookmark could not be saved. Nothing was submitted.',
        );
      }
      return;
    }
    // There has been no HTTP mutation yet; expiry/storage cannot turn this into
    // a replay. Retain any unacknowledged bookmark for its original lookup only.
    if (!_current) return;
    if (!canManage(intent.family) || !intent.current(scope(), now())) {
      try {
        await store!.resolve(original, 'never_submitted');
        if (_current) {
          state = const AdminSettingsActionState(
            message:
                'The session or request window changed before submission. Refresh the setting.',
          );
        }
      } catch (_) {
        if (_current) {
          state = AdminSettingsActionState(
            pending: pending,
            storageBlocked: true,
            message:
                'Nothing was submitted. The original bookmark still needs investigation.',
          );
        }
      }
      return;
    }
    state = AdminSettingsActionState(
      pending: pending,
      busy: true,
      message: 'Saving the original setting request…',
    );
    try {
      final receipt = await api.update(intent);
      if (!_current) return;
      receipt.validatePrepared(intent);
      original.validateReceipt(receipt);
      await store!.resolve(original, 'recorded');
      if (!_current) return;
      state = AdminSettingsActionState(
        message: receipt.changed
            ? 'Setting change recorded. Refresh to inspect the current value.'
            : 'Original request recorded. The value was already current.',
        receipt: receipt,
      );
      reload();
    } catch (_) {
      if (!_current) return;
      state = AdminSettingsActionState(
        pending: pending,
        message:
            'The original outcome is unknown. Check its request ID before making another change.',
      );
    }
  }

  Future<void> reconcile(AdminSettingsBookmark original) async {
    if (!_current ||
        state.busy ||
        original.ownerDigest != ownerDigest ||
        !state.pending.any((x) => x.digest == original.digest)) {
      return;
    }
    final pending = state.pending;
    state = AdminSettingsActionState(
      pending: pending,
      busy: true,
      storageBlocked: state.storageBlocked,
      message: 'Checking the original request…',
    );
    try {
      final result = await api.lookup(original);
      if (!_current) return;
      if (!result.sample.fresh(now())) {
        governedSettingsInvalid('expired lookup');
      }
      final resolution = result.status == 'recorded'
          ? 'recorded'
          : result.status == 'not_recorded' &&
                !result.sample.checkedAt.isBefore(original.expiresAt)
          ? 'not_recorded_after_deadline'
          : null;
      if (resolution != null) {
        if (result.receipt != null) original.validateReceipt(result.receipt!);
        if (store == null) governedSettingsInvalid('recovery storage');
        await store!.resolve(original, resolution);
        if (!_current) return;
        state = AdminSettingsActionState(
          pending: pending
              .where((x) => x.requestId != original.requestId)
              .toList(),
          message: resolution == 'recorded'
              ? 'Original request recorded. Refresh the current setting.'
              : 'No original request was recorded after its deadline. Refresh before preparing a new change.',
          receipt: result.receipt,
        );
        reload();
      } else {
        state = AdminSettingsActionState(
          pending: pending,
          message: result.status == 'in_progress'
              ? 'The original request is still in progress. Check again.'
              : 'No result is recorded yet. Its original request window remains open.',
        );
      }
    } catch (_) {
      if (!_current) return;
      state = AdminSettingsActionState(
        pending: pending,
        storageBlocked: state.storageBlocked,
        message:
            'The original request could not be verified. Sign in with the same operator and check again.',
      );
    }
  }
}
