part of 'admin_runtime.dart';

class AdminOperatingPolicyDenied implements Exception {
  const AdminOperatingPolicyDenied();
}

class AdminOperatingPolicyBusy implements Exception {
  const AdminOperatingPolicyBusy();
}

final adminOperatingPolicyProvider =
    FutureProvider.autoDispose<AdminOperatingPolicySnapshot>((ref) async {
      final scope = ref.watch(adminAuthSessionScopeProvider);
      final repository = ref.watch(adminRepositoryProvider);
      var current = true;
      ref.onDispose(() => current = false);
      final identity = await ref.watch(adminIdentityProvider.future);
      if (!current) throw const AdminSessionChanged();
      if (scope == null ||
          identity?.userId != scope.key.userId ||
          !adminOperatingPolicyCanRead(identity)) {
        throw const AdminOperatingPolicyDenied();
      }
      try {
        final raw = await repository.operatingPolicy();
        if (!current) throw const AdminSessionChanged();
        return AdminOperatingPolicySnapshot.parse(raw);
      } on CollectApiException catch (error) {
        if (!current) throw const AdminSessionChanged();
        if (error.code == '42501') throw const AdminOperatingPolicyDenied();
        if (error.code == '55P03' || error.code == '40001') {
          throw const AdminOperatingPolicyBusy();
        }
        if (error.code == 'operation_unavailable' || error.code == '501') {
          throw UnsupportedError('Unattended policy service unavailable.');
        }
        rethrow;
      } catch (_) {
        if (!current) throw const AdminSessionChanged();
        rethrow;
      }
    });
