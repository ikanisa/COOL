part of 'admin_runtime.dart';

class AdminGatewayQuery {
  const AdminGatewayQuery({
    this.limit = 20,
    this.beforeEnrolledAt,
    this.beforeDeviceId,
  });
  final int limit;
  final DateTime? beforeEnrolledAt;
  final String? beforeDeviceId;
  @override
  bool operator ==(Object other) =>
      other is AdminGatewayQuery &&
      other.limit == limit &&
      other.beforeEnrolledAt == beforeEnrolledAt &&
      other.beforeDeviceId == beforeDeviceId;
  @override
  int get hashCode => Object.hash(limit, beforeEnrolledAt, beforeDeviceId);
}

class AdminGatewayDenied implements Exception {
  const AdminGatewayDenied();
}

bool _gatewayCanRead(AdminIdentity? identity) =>
    identity?.permissions.contains('notifications.read') == true &&
    identity?.permissions.contains('system_health.read') == true;

bool _gatewayCanManage(AdminIdentity? identity) =>
    _gatewayCanRead(identity) &&
    identity?.permissions.contains('notifications.manage') == true;

final adminGatewayDevicesProvider = FutureProvider.autoDispose
    .family<AdminGatewaySnapshot, AdminGatewayQuery>((ref, query) async {
      ref.watch(adminAuthSessionScopeProvider);
      final repository = ref.watch(adminRepositoryProvider);
      var current = true;
      ref.onDispose(() => current = false);
      final identity = await ref.watch(adminIdentityProvider.future);
      if (!current) throw const AdminSessionChanged();
      if (!_gatewayCanRead(identity)) throw const AdminGatewayDenied();
      try {
        final result = await repository.gatewayDevices(
          limit: query.limit,
          beforeEnrolledAt: query.beforeEnrolledAt,
          beforeDeviceId: query.beforeDeviceId,
        );
        if (!current) throw const AdminSessionChanged();
        return AdminGatewaySnapshot.parse(
          result,
          limit: query.limit,
          beforeEnrolledAt: query.beforeEnrolledAt,
          beforeDeviceId: query.beforeDeviceId,
        );
      } on PostgrestException catch (error) {
        if (!current) throw const AdminSessionChanged();
        if (error.code == '42501') throw const AdminGatewayDenied();
        if (error.code == '42883' || error.code == 'PGRST202') {
          throw UnsupportedError('Gateway device service is unavailable.');
        }
        rethrow;
      }
    });

final adminGatewayRequestProvider = FutureProvider.autoDispose
    .family<AdminGatewayRequestSnapshot, String>((ref, requestId) async {
      ref.watch(adminAuthSessionScopeProvider);
      final repository = ref.watch(adminRepositoryProvider);
      var current = true;
      ref.onDispose(() => current = false);
      final identity = await ref.watch(adminIdentityProvider.future);
      if (!current) throw const AdminSessionChanged();
      if (!_gatewayCanRead(identity)) throw const AdminGatewayDenied();
      try {
        final result = await repository.gatewayOwnerRequest(requestId);
        if (!current) throw const AdminSessionChanged();
        return AdminGatewayRequestSnapshot.parse(result, requestId: requestId);
      } on PostgrestException catch (error) {
        if (!current) throw const AdminSessionChanged();
        if (error.code == '42501') throw const AdminGatewayDenied();
        if (error.code == '42883' || error.code == 'PGRST202') {
          throw UnsupportedError('Gateway request lookup is unavailable.');
        }
        rethrow;
      }
    });
