part of 'admin_runtime.dart';

typedef AdminReceiptPrincipalDirectoryAccess = ({
  AdminReceiptPrincipalDirectoryQuery query,
  AdminSessionScope session,
});
typedef AdminReceiptPrincipalIdentityAccess = ({
  String principalId,
  AdminSessionScope session,
});

final adminReceiptPrincipalsProvider = FutureProvider.autoDispose
    .family<
      AdminReceiptPrincipalDirectory,
      AdminReceiptPrincipalDirectoryAccess
    >((ref, access) async {
      final session = ref.watch(adminAuthSessionScopeProvider);
      ref.watch(_adminIdentityRevisionProvider);
      final repository = ref.watch(adminRepositoryProvider);
      var current = true;
      ref.onDispose(() => current = false);
      if (session != access.session) throw const AdminSessionChanged();
      final identity = await ref.watch(adminIdentityProvider.future);
      if (!current) throw const AdminSessionChanged();
      if (identity?.userId != session?.key.userId ||
          !adminReceiptOperationsCanManage(identity)) {
        throw const AdminReceiptOperationsDenied();
      }
      final raw = await repository
          .receiptPrincipals(access.query)
          .timeout(const Duration(seconds: 15));
      if (!current) throw const AdminSessionChanged();
      return AdminReceiptPrincipalDirectory.parse(raw, query: access.query);
    });

final adminReceiptPrincipalProvider = FutureProvider.autoDispose
    .family<
      AdminReceiptPrincipalObservation,
      AdminReceiptPrincipalIdentityAccess
    >((ref, access) async {
      final session = ref.watch(adminAuthSessionScopeProvider);
      ref.watch(_adminIdentityRevisionProvider);
      final repository = ref.watch(adminRepositoryProvider);
      var current = true;
      ref.onDispose(() => current = false);
      if (session != access.session) throw const AdminSessionChanged();
      final identity = await ref.watch(adminIdentityProvider.future);
      if (!current) throw const AdminSessionChanged();
      if (identity?.userId != session?.key.userId ||
          !adminReceiptOperationsCanManage(identity)) {
        throw const AdminReceiptOperationsDenied();
      }
      final raw = await repository
          .receiptPrincipal(access.principalId)
          .timeout(const Duration(seconds: 15));
      if (!current) throw const AdminSessionChanged();
      return AdminReceiptPrincipalObservation.parse(
        raw,
        principalId: access.principalId,
      );
    });

final adminReceiptPrincipalCheckpointStoreProvider =
    Provider<AdminReceiptPrincipalCheckpointStore?>(
      (ref) => browserAdminReceiptPrincipalCheckpointStore(),
    );

final adminReceiptPrincipalControllerProvider =
    StateNotifierProvider.autoDispose<
      AdminReceiptPrincipalController,
      AdminReceiptPrincipalControlState
    >((ref) {
      final session = ref.watch(adminAuthSessionScopeProvider);
      final identity = _adminResolvedIdentity(ref.watch(adminIdentityProvider));
      final revision = ref.watch(_adminIdentityRevisionProvider);
      final repository = ref.watch(adminRepositoryProvider);
      final store = ref.watch(adminReceiptPrincipalCheckpointStoreProvider);
      final clock = ref.watch(adminClockProvider);
      final enabled =
          session != null &&
          identity?.userId == session.key.userId &&
          adminReceiptOperationsCanManage(identity);
      var active = true;
      ref.onDispose(() => active = false);
      bool current() {
        if (!active) return false;
        final resolved = _adminResolvedIdentity(
          ref.read(adminIdentityProvider),
        );
        final valid =
            enabled &&
            ref.read(adminAuthSessionScopeProvider) == session &&
            ref.read(_adminIdentityRevisionProvider) == revision &&
            identical(repository, ref.read(adminRepositoryProvider)) &&
            resolved?.userId == session.key.userId &&
            adminReceiptOperationsCanManage(resolved);
        if (!valid) active = false;
        return valid;
      }

      return AdminReceiptPrincipalController(
        ownerDigest: enabled
            ? adminReceiptPrincipalOwnerDigest(session.key.userId)
            : '0000000000000000000000000000000000000000000000000000000000000000',
        store: enabled ? store : null,
        now: clock,
        isCurrent: current,
        preflight: (intent) async {
          if (!current()) return false;
          if (intent.action == AdminReceiptPrincipalAction.enroll) return true;
          final raw = await repository
              .receiptPrincipal(intent.principalId!)
              .timeout(const Duration(seconds: 15));
          if (!current()) return false;
          final observed = AdminReceiptPrincipalObservation.parse(
            raw,
            principalId: intent.principalId!,
          );
          final target = observed.identity;
          if (!observed.isFresh(clock()) ||
              target == null ||
              target.keySha256 != intent.keySha256 ||
              target.expiresAt != intent.identityExpiresAt) {
            return false;
          }
          return intent.action == AdminReceiptPrincipalAction.activate
              ? target.state == AdminReceiptPrincipalState.pending &&
                    !target.isExpired(clock())
              : target.state != AdminReceiptPrincipalState.revoked;
        },
        send: repository.receiptPrincipalAction,
        lookup: repository.receiptPrincipalOwnerRequest,
      );
    });
