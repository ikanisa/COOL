import 'admin_models.dart';

export 'admin_models.dart';
export 'admin_runtime.dart';

abstract class AdminRepositoryBase {
  const AdminRepositoryBase();

  Future<void> sendOtp({required String phone});

  Future<AdminIdentity?> verifyOtp({
    required String phone,
    required String otp,
  });

  Future<void> signOut();

  Future<AdminIdentity?> currentIdentity();

  Future<List<AdminMetric>> overviewMetrics();

  Future<AdminListResult> list(
    String rpcName, {
    String? search,
    String? status,
    int? limit,
    int? offset,
    String? sortBy,
    String? countryCode,
  });

  Future<Map<String, dynamic>> detail(String rpcName, String id);

  Future<AdminQueueSla?> queueSla(String queueKey) async => null;

  Future<AdminRuntimeConfig?> runtimeConfig() async => null;

  Future<Map<String, dynamic>> action(
    String rpcName,
    Map<String, dynamic> params,
  );

  Future<Map<String, dynamic>> prepareRosterImport(Map<String, dynamic> body) =>
      throw UnsupportedError('Roster import preview is not available.');
}
