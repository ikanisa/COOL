part of 'admin_runtime.dart';

class AdminReceiptCancelDenied implements Exception {
  const AdminReceiptCancelDenied();
}

class AdminReceiptCancelBusy implements Exception {
  const AdminReceiptCancelBusy();
}

bool _receiptCancelCanRead(AdminIdentity? identity) =>
    identity?.roles.contains('platform_owner') == true &&
    {
      'payments.read',
      'notifications.read',
      'system_health.read',
    }.every(identity!.permissions.contains);
bool _receiptCancelCanManage(AdminIdentity? identity) =>
    _receiptCancelCanRead(identity) &&
    identity!.permissions.contains('notifications.manage');
final adminReceiptCancelCheckpointStoreProvider =
    Provider<AdminReceiptCancelCheckpointStore?>(
      (ref) => browserAdminReceiptCancelCheckpointStore(),
    );
final adminReceiptCancelInspectionProvider = FutureProvider.autoDispose
    .family<AdminReceiptCancelInspection, String>((ref, id) async {
      ref.watch(adminAuthSessionScopeProvider);
      final repository = ref.watch(adminRepositoryProvider);
      var current = true;
      ref.onDispose(() => current = false);
      final identity = await ref.watch(adminIdentityProvider.future);
      if (!current) throw const AdminSessionChanged();
      if (!_receiptCancelCanRead(identity)) {
        throw const AdminReceiptCancelDenied();
      }
      try {
        final raw = await repository.inspectUnstartedReceipt(id);
        if (!current) throw const AdminSessionChanged();
        return AdminReceiptCancelInspection.parse(raw, outboxId: id);
      } on PostgrestException catch (error) {
        if (!current) throw const AdminSessionChanged();
        _receiptCancelReadError(error);
        rethrow;
      }
    });
final adminReceiptCancelLookupProvider = FutureProvider.autoDispose
    .family<AdminReceiptCancelLookup, String>((ref, id) async {
      ref.watch(adminAuthSessionScopeProvider);
      final repository = ref.watch(adminRepositoryProvider);
      var current = true;
      ref.onDispose(() => current = false);
      final identity = await ref.watch(adminIdentityProvider.future);
      if (!current) throw const AdminSessionChanged();
      if (!_receiptCancelCanRead(identity)) {
        throw const AdminReceiptCancelDenied();
      }
      try {
        final raw = await repository.unstartedReceiptAction(id);
        if (!current) throw const AdminSessionChanged();
        return AdminReceiptCancelLookup.parse(raw, requestId: id);
      } on PostgrestException catch (error) {
        if (!current) throw const AdminSessionChanged();
        _receiptCancelReadError(error);
        rethrow;
      }
    });
void _receiptCancelReadError(PostgrestException error) {
  if (error.code == '42501') throw const AdminReceiptCancelDenied();
  if (error.code == '55P03') throw const AdminReceiptCancelBusy();
  if ({'42883', 'PGRST202'}.contains(error.code)) {
    throw UnsupportedError('Safe receipt cancellation service unavailable.');
  }
}
