import 'admin_roster_import.dart';
import 'admin_models.dart';
import 'admin_reconciliation_models.dart';
import 'admin_gateway_contracts.dart';

export 'admin_models.dart';
export 'admin_reconciliation_models.dart';
export 'admin_runtime.dart';

abstract class AdminRepositoryBase {
  const AdminRepositoryBase();

  Future<void> sendOtp({required String phone});

  Future<AdminIdentity?> verifyOtp({
    required String phone,
    required String otp,
  });

  Future<void> sendEmailOtp({required String email}) =>
      throw UnsupportedError('Admin email sign-in is unavailable.');

  Future<AdminIdentity?> verifyEmailOtp({
    required String email,
    required String otp,
  }) => throw UnsupportedError('Admin email sign-in is unavailable.');

  Future<void> signOut();

  Future<AdminIdentity?> currentIdentity();

  Future<List<AdminMetric>> overviewMetrics();

  Future<Map<String, dynamic>> receiptOverview({String? countryCode}) =>
      throw UnsupportedError('Receipt Overview measurements are unavailable.');

  Future<Map<String, dynamic>> investigation({
    required String kind,
    required String id,
  }) => throw UnsupportedError('Joined investigation service is unavailable.');

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

  Future<Map<String, dynamic>> smsQueueHealth() =>
      throw UnsupportedError('SMS queue health is not available.');

  Future<Map<String, dynamic>> shadowRuns({
    int limit = 20,
    DateTime? beforeStartedAt,
    String? beforeRunId,
  }) => throw UnsupportedError('Manual shadow run history is not available.');

  Future<Map<String, dynamic>> gatewayDevices({
    int limit = 20,
    DateTime? beforeEnrolledAt,
    String? beforeDeviceId,
  }) => throw UnsupportedError('SMS Gateway device reads are unavailable.');

  Future<Map<String, dynamic>> gatewayOwnerRequest(String requestId) =>
      throw UnsupportedError('Gateway request lookup is unavailable.');

  Future<AdminGatewayActionReceipt> gatewayOwnerAction(
    AdminGatewayOwnerIntent intent,
  ) => throw UnsupportedError('Gateway device changes are unavailable.');

  Future<Map<String, dynamic>> action(
    String rpcName,
    Map<String, dynamic> params,
  );

  AdminRosterGateway openRosterImport() =>
      throw UnsupportedError('Roster imports require a live Admin session.');

  Future<Map<String, dynamic>> prepareRosterImport(Map<String, dynamic> body) =>
      throw UnsupportedError('Roster import preview is not available.');

  Future<AdminListResult> paymentReconciliationReviews(
    String? paymentId, {
    int limit = 25,
    int offset = 0,
  }) => throw UnsupportedError('Reconciliation history is not available.');

  Future<Map<String, dynamic>> paymentReconciliationDetail(
    String reviewId, {
    required String paymentId,
  }) => throw UnsupportedError('Reconciliation evidence is not available.');

  Future<String> proposePaymentReconciliation(Map<String, dynamic> evidence) =>
      throw UnsupportedError('Reconciliation proposals are not available.');

  Future<void> approvePaymentReconciliation(String reviewId, String reason) =>
      throw UnsupportedError('Reconciliation approval is not available.');

  Future<AdminReconciliationFinalization> finalizePaymentReconciliation(
    String reviewId, {
    required String paymentId,
  }) => throw UnsupportedError('Reconciliation finalization is not available.');
}
