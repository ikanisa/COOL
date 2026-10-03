import 'admin_roster_import.dart';
import 'admin_models.dart';
import 'admin_receipt_operational_history_sdk.dart';
import 'admin_reconciliation_models.dart';
import 'admin_gateway_contracts.dart';
import 'admin_automatic_gateway_models.dart';
import 'admin_exception_models.dart';
import 'admin_exception_workflow_models.dart';
import 'admin_exception_followup_v2_models.dart';
import 'admin_receipt_cancel_models.dart';
import 'admin_entity_audit.dart';
import 'admin_exception_escalation_inbox_v2_models.dart';
import 'admin_receipt_operations_models.dart';
import 'admin_receipt_principal_models.dart';
import 'admin_governed_settings_sdk.dart';

export 'admin_models.dart';
export 'admin_reconciliation_models.dart';
export 'admin_runtime.dart';

abstract class AdminRepositoryBase {
  const AdminRepositoryBase();

  AdminGovernedSettingsApi get governedSettings =>
      throw UnsupportedError('Governed Settings are unavailable.');

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

  Future<Map<String, dynamic>> inspectUnstartedReceipt(String outboxId) =>
      throw UnsupportedError('Safe receipt cancellation service unavailable.');
  Future<AdminReceiptCancelReceipt> cancelUnstartedReceipt(
    AdminReceiptCancelIntent intent,
  ) => throw UnsupportedError('Safe receipt cancellation service unavailable.');
  Future<Map<String, dynamic>> unstartedReceiptAction(String requestId) =>
      throw UnsupportedError('Safe receipt cancellation service unavailable.');

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

  AdminReceiptOperationalHistoryApi get receiptOperationalHistory =>
      throw UnsupportedError('Receipt operational history is unavailable.');

  Future<Map<String, dynamic>> receiptOperationalTelemetry() =>
      throw UnsupportedError('Receipt operational telemetry is unavailable.');

  Future<Map<String, dynamic>> receiptExceptionWorkerHealth() =>
      throw UnsupportedError('Receipt exception worker health is unavailable.');

  Future<Map<String, dynamic>> receiptWorkerTransport(
    String requestId, {
    required DateTime expectedExpiresAt,
  }) => throw UnsupportedError('Receipt worker transport is unavailable.');

  Future<Map<String, dynamic>> receiptPrincipals(
    AdminReceiptPrincipalDirectoryQuery query,
  ) => throw UnsupportedError('Receipt operations identities are unavailable.');

  Future<Map<String, dynamic>> receiptPrincipal(String principalId) =>
      throw UnsupportedError('Receipt operations identity is unavailable.');

  Future<Map<String, dynamic>> receiptPrincipalAction(
    AdminReceiptPrincipalIntent intent,
  ) => throw UnsupportedError('Receipt identity actions are unavailable.');

  Future<Map<String, dynamic>> receiptPrincipalOwnerRequest(
    AdminReceiptPrincipalBinding original,
  ) =>
      throw UnsupportedError('Receipt identity request lookup is unavailable.');

  Future<Map<String, dynamic>> operatingPolicy() =>
      throw UnsupportedError('Unattended policy service is unavailable.');

  Future<Map<String, dynamic>> receiptOperationsPolicy() =>
      throw UnsupportedError('Receipt operations policy is unavailable.');
  Future<Map<String, dynamic>> configureReceiptOperations(
    AdminReceiptOperationsIntent intent,
  ) => throw UnsupportedError('Receipt operations controls are unavailable.');
  Future<Map<String, dynamic>> receiptOperationsOwnerRequest(
    String requestId,
  ) => throw UnsupportedError(
    'Receipt operations request lookup is unavailable.',
  );

  Future<Map<String, dynamic>> exceptionWorkflow(String exceptionId) =>
      throw UnsupportedError('Exception follow-up service is unavailable.');
  Future<Map<String, dynamic>> receiptDeferralEvidence(String exceptionId) =>
      throw UnsupportedError('Receipt deferral evidence is unavailable.');
  Future<Map<String, dynamic>> exceptionWorkflowAction(
    AdminExceptionWorkflowIntent intent,
  ) => throw UnsupportedError('Exception follow-up service is unavailable.');
  Future<Map<String, dynamic>> exceptionWorkflowRequest(String requestId) =>
      throw UnsupportedError('Exception follow-up service is unavailable.');
  Future<Map<String, dynamic>> exceptionFollowupOperators(
    AdminExceptionFollowupDirectoryQuery query,
  ) => throw UnsupportedError('Eligible exception operators are unavailable.');
  Future<Map<String, dynamic>> exceptionFollowupAction(
    AdminExceptionWorkflowIntent intent,
  ) => throw UnsupportedError('Bound exception follow-up is unavailable.');
  Future<Map<String, dynamic>> exceptionFollowupRequest(
    AdminExceptionFollowupReference original,
  ) => throw UnsupportedError(
    'Bound exception follow-up lookup is unavailable.',
  );
  Future<Map<String, dynamic>> exceptionEscalationInbox() =>
      throw UnsupportedError('Exception escalation inbox is unavailable.');
  Future<Map<String, dynamic>> readExceptionEscalation(String escalationId) =>
      throw UnsupportedError('Exception escalation inbox is unavailable.');

  Future<Map<String, dynamic>> shadowRuns({
    int limit = 20,
    DateTime? beforeStartedAt,
    String? beforeRunId,
  }) => throw UnsupportedError('Manual shadow run history is not available.');

  Future<Map<String, dynamic>> operatorEntityAudit(
    AdminEntityAuditQuery query,
  ) => throw UnsupportedError('Entity action history is unavailable.');

  Future<Map<String, dynamic>> exceptionEntityAudit(
    AdminEntityAuditQuery query,
  ) =>
      throw UnsupportedError('Joined exception action history is unavailable.');

  Future<Map<String, dynamic>> exceptionEscalationInboxPage(
    AdminExceptionEscalationInboxQuery query,
  ) => throw UnsupportedError('Paged escalation inbox is unavailable.');

  Future<Map<String, dynamic>> readExceptionEscalationCurrent(String id) =>
      throw UnsupportedError('Current escalation opening is unavailable.');

  Future<Map<String, dynamic>> gatewayDevices({
    int limit = 20,
    DateTime? beforeEnrolledAt,
    String? beforeDeviceId,
  }) => throw UnsupportedError('SMS Gateway device reads are unavailable.');

  Future<Map<String, dynamic>> gatewayOwnerRequest(String requestId) =>
      throw UnsupportedError('Gateway request lookup is unavailable.');

  Future<Map<String, dynamic>> automaticReceiptEvidence(
    String receiptId, {
    int limit = 20,
    AdminAutomaticHistoryCursor? before,
  }) =>
      throw UnsupportedError('Automatic gateway investigation is unavailable.');

  Future<Map<String, dynamic>> automaticDeviceAttempts(
    String deviceId, {
    int limit = 20,
    AdminAutomaticDeviceCursor? before,
  }) => throw UnsupportedError(
    'Automatic gateway attempt history is unavailable.',
  );

  Future<AdminGatewayActionReceipt> gatewayOwnerAction(
    AdminGatewayOwnerIntent intent,
  ) => throw UnsupportedError('Gateway device changes are unavailable.');

  Future<Map<String, dynamic>> exceptionInbox({
    bool active = true,
    int limit = 20,
    AdminExceptionSource? source,
    DateTime? beforeChangedAt,
    String? beforeId,
  }) => throw UnsupportedError('Exception inbox service is unavailable.');

  Future<Map<String, dynamic>> exceptionActionLookup(String requestId) =>
      throw UnsupportedError('Exception request lookup is unavailable.');

  Future<AdminExceptionReceipt> exceptionAction(AdminExceptionIntent intent) =>
      throw UnsupportedError('Exception review actions are unavailable.');

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
