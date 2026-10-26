part of 'admin_runtime.dart';

class AdminEntityAuditDenied implements Exception {
  const AdminEntityAuditDenied();
}

class AdminEntityAuditAuthorityBusy implements Exception {
  const AdminEntityAuditAuthorityBusy();
}

final adminEntityAuditProvider = FutureProvider.autoDispose
    .family<AdminEntityAuditSnapshot, AdminEntityAuditQuery>((
      ref,
      query,
    ) async {
      query.validate();
      final scope = ref.watch(adminAuthSessionScopeProvider);
      final repository = ref.watch(adminRepositoryProvider);
      var current = true;
      ref.onDispose(() => current = false);
      final identity = await ref.watch(adminIdentityProvider.future);
      if (!current) throw const AdminSessionChanged();
      if (scope == null ||
          identity?.userId != scope.key.userId ||
          !adminEntityAuditCanRead(identity, query.kind)) {
        throw const AdminEntityAuditDenied();
      }
      try {
        final raw = await repository.operatorEntityAudit(query);
        if (!current) throw const AdminSessionChanged();
        return AdminEntityAuditSnapshot.parse(raw, query: query);
      } on CollectApiException catch (error) {
        if (!current) throw const AdminSessionChanged();
        if (error.code == '42501') throw const AdminEntityAuditDenied();
        if (error.code == '55P03' || error.code == '40001') {
          throw const AdminEntityAuditAuthorityBusy();
        }
        if (error.code == 'operation_unavailable' || error.code == '501') {
          throw UnsupportedError('Entity action history is unavailable.');
        }
        rethrow;
      } catch (_) {
        if (!current) throw const AdminSessionChanged();
        rethrow;
      }
    });
