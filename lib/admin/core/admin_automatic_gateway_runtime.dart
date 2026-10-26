part of 'admin_runtime.dart';

typedef AdminAutomaticReceiptQuery = ({
  String receiptId,
  int limit,
  AdminAutomaticHistoryCursor? before,
});
typedef AdminAutomaticDeviceQuery = ({
  String deviceId,
  int limit,
  AdminAutomaticDeviceCursor? before,
});

void _automaticGatewayInput(
  String id,
  int limit,
  DateTime? at,
  String? cursorId,
) {
  gatewayUuid(id);
  if (limit < 1 || limit > 25) throw RangeError.range(limit, 1, 25, 'limit');
  if ((at == null) != (cursorId == null) ||
      at != null && (at.year < 1 || at.year > 9999)) {
    throw const FormatException(
      'A complete automatic gateway cursor is required.',
    );
  }
  if (cursorId != null) gatewayUuid(cursorId);
}

Future<T> _automaticGatewayRead<T>(
  Ref ref,
  Future<T> Function(AdminRepositoryBase) read,
) async {
  final scope = ref.watch(adminAuthSessionScopeProvider);
  final repository = ref.watch(adminRepositoryProvider);
  var current = true;
  ref.onDispose(() => current = false);
  final identity = await ref.watch(adminIdentityProvider.future);
  if (!current) throw const AdminSessionChanged();
  if (!_gatewayCanRead(identity)) throw const AdminGatewayDenied();
  try {
    final result = await read(repository);
    if (!current ||
        ref.read(adminAuthSessionScopeProvider) != scope ||
        !identical(ref.read(adminRepositoryProvider), repository)) {
      throw const AdminSessionChanged();
    }
    return result;
  } on CollectApiException catch (error) {
    if (!current) throw const AdminSessionChanged();
    if (error.code == '42501') throw const AdminGatewayDenied();
    if (error.code == 'operation_unavailable' || error.code == '501') {
      throw UnsupportedError('Automatic gateway investigation is unavailable.');
    }
    rethrow;
  }
}

final adminAutomaticReceiptProvider = FutureProvider.autoDispose
    .family<AdminAutomaticReceiptEvidence, AdminAutomaticReceiptQuery>(
      (ref, query) => _automaticGatewayRead(
        ref,
        (repository) async => AdminAutomaticReceiptEvidence.parse(
          await repository.automaticReceiptEvidence(
            query.receiptId,
            limit: query.limit,
            before: query.before,
          ),
          receiptId: query.receiptId,
          limit: query.limit,
          before: query.before,
        ),
      ),
    );

final adminAutomaticDeviceProvider = FutureProvider.autoDispose
    .family<AdminAutomaticDeviceEvidence, AdminAutomaticDeviceQuery>(
      (ref, query) => _automaticGatewayRead(
        ref,
        (repository) async => AdminAutomaticDeviceEvidence.parse(
          await repository.automaticDeviceAttempts(
            query.deviceId,
            limit: query.limit,
            before: query.before,
          ),
          deviceId: query.deviceId,
          limit: query.limit,
          before: query.before,
        ),
      ),
    );
