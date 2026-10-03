part of 'admin_runtime.dart';

bool adminReceiptOperationalHistoryCanRead(AdminIdentity? identity) =>
    identity != null &&
    identity.roles.contains('platform_owner') &&
    const [
      'payments.read',
      'notifications.read',
      'system_health.read',
    ].every(identity.permissions.contains);

class AdminReceiptHistoryDenied implements Exception {
  const AdminReceiptHistoryDenied();
}

Future<T> _receiptHistoryRead<T>(
  Ref ref,
  Future<T> Function(AdminReceiptOperationalHistoryApi api) read,
) async {
  final session = ref.watch(adminAuthSessionScopeProvider);
  ref.watch(_adminIdentityRevisionProvider);
  ref.watch(adminRealtimeTickProvider);
  final repository = ref.watch(adminRepositoryProvider);
  var retained = true;
  ref.onDispose(() => retained = false);
  final identity = await ref.watch(adminIdentityProvider.future);
  if (!retained) throw const AdminSessionChanged();
  if (session == null ||
      identity?.userId != session.key.userId ||
      !adminReceiptOperationalHistoryCanRead(identity)) {
    throw const AdminReceiptHistoryDenied();
  }
  final revision = ref.read(_adminIdentityRevisionProvider),
      roles = Set.of(identity!.roles),
      permissions = Set.of(identity.permissions);
  bool current() {
    if (!retained) return false;
    final actor = _adminResolvedIdentity(ref.read(adminIdentityProvider));
    return ref.read(adminAuthSessionScopeProvider) == session &&
        identical(ref.read(adminRepositoryProvider), repository) &&
        ref.read(_adminIdentityRevisionProvider) == revision &&
        actor?.userId == identity.userId &&
        actor!.roles.length == roles.length &&
        roles.containsAll(actor.roles) &&
        actor.permissions.length == permissions.length &&
        permissions.containsAll(actor.permissions);
  }

  if (!current()) throw const AdminSessionChanged();
  try {
    final value = await read(repository.receiptOperationalHistory);
    if (!current()) throw const AdminSessionChanged();
    return value;
  } on PostgrestException catch (e) {
    if (!current()) throw const AdminSessionChanged();
    if (e.code == '42501') throw const AdminReceiptHistoryDenied();
    if ({'42883', 'PGRST202'}.contains(e.code)) {
      throw UnsupportedError('Receipt operational history is unavailable.');
    }
    rethrow;
  } catch (_) {
    if (!current()) throw const AdminSessionChanged();
    rethrow;
  }
}

final adminReceiptHistoryPageProvider = FutureProvider.autoDispose
    .family<AdminReceiptHistoryPage, AdminReceiptHistoryQuery>(
      (ref, q) => _receiptHistoryRead(ref, (api) => api.page(q)),
    );
final adminReceiptOperationalRunProvider = FutureProvider.autoDispose
    .family<AdminReceiptOperationalRun, String>(
      (ref, id) => _receiptHistoryRead(ref, (api) => api.run(id)),
    );

/// Reuses the current Admin session, identity revision and repository fence for
/// links from investigation evidence into the operational reader.
class AdminReceiptOperationalHistoryNavigationScope {
  AdminReceiptOperationalHistoryNavigationScope(WidgetRef ref)
    : _scope = _AdminActionScope(ref) {
    ref.watch(adminAuthSessionScopeProvider);
    ref.watch(adminRepositoryProvider);
    ref.watch(_adminIdentityRevisionProvider);
    ref.watch(adminIdentityProvider);
  }
  final _AdminActionScope _scope;
  bool get isCurrent =>
      _scope.session != null &&
      _scope.session!.key.userId == _scope.actorId &&
      _scope.isCurrent &&
      adminReceiptOperationalHistoryCanRead(
        _adminResolvedIdentity(_scope.ref.read(adminIdentityProvider)),
      );
}
