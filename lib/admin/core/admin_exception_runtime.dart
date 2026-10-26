part of 'admin_runtime.dart';

class AdminExceptionQuery {
  const AdminExceptionQuery({
    this.active = true,
    this.limit = 20,
    this.source,
    this.beforeChangedAt,
    this.beforeId,
  });
  final bool active;
  final int limit;
  final AdminExceptionSource? source;
  final DateTime? beforeChangedAt;
  final String? beforeId;
  @override
  bool operator ==(Object other) =>
      other is AdminExceptionQuery &&
      active == other.active &&
      limit == other.limit &&
      source == other.source &&
      beforeChangedAt == other.beforeChangedAt &&
      beforeId == other.beforeId;
  @override
  int get hashCode =>
      Object.hash(active, limit, source, beforeChangedAt, beforeId);
}

class AdminExceptionDenied implements Exception {
  const AdminExceptionDenied();
}

class AdminExceptionAuthorityBusy implements Exception {
  const AdminExceptionAuthorityBusy();
}

bool _exceptionCanRead(AdminIdentity? identity) =>
    identity != null &&
    {
      'payments.read',
      'notifications.read',
      'system_health.read',
    }.every(identity.permissions.contains);
bool _exceptionCanManage(AdminIdentity? identity) =>
    _exceptionCanRead(identity) &&
    identity!.permissions.contains('notifications.manage');

final adminExceptionCheckpointStoreProvider =
    Provider<AdminExceptionCheckpointStore?>(
      (ref) => browserAdminExceptionCheckpointStore(),
    );

final adminExceptionInboxProvider = FutureProvider.autoDispose
    .family<AdminExceptionSnapshot, AdminExceptionQuery>((ref, query) async {
      ref.watch(adminAuthSessionScopeProvider);
      final repository = ref.watch(adminRepositoryProvider);
      var current = true;
      ref.onDispose(() => current = false);
      final identity = await ref.watch(adminIdentityProvider.future);
      if (!current) throw const AdminSessionChanged();
      if (!_exceptionCanRead(identity)) throw const AdminExceptionDenied();
      try {
        final raw = await repository.exceptionInbox(
          active: query.active,
          limit: query.limit,
          source: query.source,
          beforeChangedAt: query.beforeChangedAt,
          beforeId: query.beforeId,
        );
        if (!current) throw const AdminSessionChanged();
        return AdminExceptionSnapshot.parse(
          raw,
          active: query.active,
          limit: query.limit,
          source: query.source,
          beforeChangedAt: query.beforeChangedAt,
          beforeId: query.beforeId,
        );
      } on CollectApiException catch (error) {
        if (!current) throw const AdminSessionChanged();
        if (error.code == '42501') throw const AdminExceptionDenied();
        if (error.code == 'operation_unavailable' || error.code == '501') {
          throw UnsupportedError('Exception inbox service is unavailable.');
        }
        rethrow;
      }
    });

final adminExceptionLookupProvider = FutureProvider.autoDispose
    .family<AdminExceptionLookup, String>((ref, requestId) async {
      ref.watch(adminAuthSessionScopeProvider);
      final repository = ref.watch(adminRepositoryProvider);
      var current = true;
      ref.onDispose(() => current = false);
      final identity = await ref.watch(adminIdentityProvider.future);
      if (!current) throw const AdminSessionChanged();
      if (!_exceptionCanRead(identity)) throw const AdminExceptionDenied();
      try {
        final raw = await repository.exceptionActionLookup(requestId);
        if (!current) throw const AdminSessionChanged();
        return AdminExceptionLookup.parse(raw, requestId: requestId);
      } on CollectApiException catch (error) {
        if (!current) throw const AdminSessionChanged();
        if (error.code == '42501') throw const AdminExceptionDenied();
        if (error.code == '55P03') throw const AdminExceptionAuthorityBusy();
        if (error.code == 'operation_unavailable' || error.code == '501') {
          throw UnsupportedError('Exception request lookup is unavailable.');
        }
        rethrow;
      }
    });
