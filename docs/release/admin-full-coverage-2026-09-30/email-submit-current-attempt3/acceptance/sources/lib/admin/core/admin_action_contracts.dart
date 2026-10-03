import '../../shared/repositories/runtime_control_contract.dart';
import '../../core/data/exact_json_values.dart';
import 'admin_read_contracts.dart';
import 'admin_email_otp.dart';
import 'admin_operator_approval.dart';
import 'admin_gateway_contracts.dart';

/// Action receipts match the installed SQL contracts. Fields that the backend
/// does not return (for example notification event ID) are not invented here.
void validateAdminActionReceipt(
  String operation,
  Map<String, dynamic> request,
  Map<String, dynamic> response,
) {
  final uuid = RegExp(r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$');
  bool id(Object? value) => value is String && uuid.hasMatch(value);
  bool keys(String names) {
    final expected = names.split(' ').toSet();
    return response.length == expected.length &&
        response.keys.toSet().containsAll(expected);
  }

  bool bound(String field, String parameter) =>
      id(request[parameter]) && response[field] == request[parameter];
  final ok = response['ok'] == true;
  bool reason() =>
      request['p_reason'] is String &&
      (request['p_reason'] as String).trim().length >= 8 &&
      (request['p_reason'] as String).trim().length <= 500;
  bool email() {
    try {
      return request['p_email'] is String &&
          normalizeAdminEmail(request['p_email'] as String) ==
              request['p_email'];
    } on FormatException {
      return false;
    }
  }

  final valid = switch (operation) {
    'admin_enroll_gateway_device_v1' ||
    'admin_activate_gateway_device_v1' ||
    'admin_revoke_gateway_device_v1' =>
      adminGatewayActionReceiptMatches(operation, request, response),
    'admin_retry_notification' =>
      keys('ok status delivery_count') &&
          ok &&
          response['status'] == 'queued' &&
          response['delivery_count'] is int &&
          (response['delivery_count'] as int) > 0 &&
          (response['delivery_count'] as int) <= maxExactJsonInteger,
    'admin_create_platform_public_group' =>
      keys('ok collection_id payee_id status visibility route_immutable') &&
          ok &&
          id(response['collection_id']) &&
          id(response['payee_id']) &&
          response['status'] == 'active' &&
          response['visibility'] == 'public_approved' &&
          response['route_immutable'] == true,
    'admin_set_group_active' =>
      keys('ok collection_id active status visibility') &&
          ok &&
          bound('collection_id', 'p_collection_id') &&
          request['p_active'] is bool &&
          response['active'] == request['p_active'] &&
          response['status'] ==
              (request['p_active'] == true ? 'active' : 'inactive') &&
          (request['p_active'] == true
              ? {'private', 'public_approved'}.contains(response['visibility'])
              : response['visibility'] == 'archived'),
    'admin_update_platform_public_group_metadata' =>
      keys('ok collection_id public_status receiver_id visibility status') &&
          ok &&
          bound('collection_id', 'p_collection_id') &&
          id(response['receiver_id']) &&
          response['public_status'] == 'public_approved' &&
          {
            'private',
            'public_requested',
            'public_approved',
            'public_rejected',
            'archived',
          }.contains(response['visibility']) &&
          {'active', 'inactive'}.contains(response['status']),
    'admin_update_collection_support_status' =>
      keys('ok status') &&
          ok &&
          request['p_status'] is String &&
          response['status'] == request['p_status'],
    'admin_create_collect_payee' =>
      keys('ok payee_id status route_immutable') &&
          ok &&
          id(response['payee_id']) &&
          response['status'] == 'active' &&
          response['route_immutable'] == true,
    'admin_update_collect_payee' =>
      keys('ok payee_id label route_immutable') &&
          ok &&
          bound('payee_id', 'p_payee_id') &&
          request['p_label'] is String &&
          response['label'] == (request['p_label'] as String).trim() &&
          response['route_immutable'] == true,
    'admin_set_collect_payee_status' =>
      keys('ok payee_id status route_immutable') &&
          ok &&
          bound('payee_id', 'p_payee_id') &&
          request['p_active'] is bool &&
          response['status'] ==
              (request['p_active'] == true ? 'active' : 'inactive') &&
          response['route_immutable'] == true,
    'admin_set_feature_flag_v2' =>
      keys(
            'contract_version ok previous_revision revision changed updated_at key enabled',
          ) &&
          request['p_key'] is String &&
          (request['p_key'] as String).length <= 128 &&
          RegExp(r'^[a-z0-9_.-]+$').hasMatch(request['p_key'] as String) &&
          response['key'] == request['p_key'] &&
          request['p_enabled'] is bool &&
          response['enabled'] == request['p_enabled'] &&
          runtimeRevision(request['p_expected_revision'], minimum: 1) &&
          runtimeRevisionAck(response, request['p_expected_revision'] as int),
    'admin_record_operator_note' =>
      keys('ok note_id') && ok && id(response['note_id']),
    'admin_reparse_payment_event' =>
      keys('ok message') &&
          ok &&
          response['message'] == 'Reparse queued for review',
    'admin_reveal_raw_sms' =>
      keys('ok message') && ok && response['message'] is String,
    'admin_manual_allocate_payment' =>
      keys('status payment_id') &&
          response['status'] == 'allocated' &&
          id(response['payment_id']),
    'admin_approve_whatsapp' || 'admin_revoke_whatsapp_approval' =>
      keys('ok status user_id') &&
          ok &&
          bound('user_id', 'p_user_id') &&
          response['status'] ==
              (operation == 'admin_approve_whatsapp' ? 'approved' : 'revoked'),
    'admin_approve_email_operator_v1' || 'admin_revoke_email_operator_v1' =>
      keys('ok status user_id') &&
          ok &&
          bound('user_id', 'p_user_id') &&
          reason() &&
          request.length ==
              (operation == 'admin_approve_email_operator_v1' ? 3 : 2) &&
          (operation != 'admin_approve_email_operator_v1' || email()) &&
          response['status'] ==
              (operation == 'admin_approve_email_operator_v1'
                  ? 'approved'
                  : 'revoked'),
    'admin_set_user_access' =>
      keys('ok status') &&
          ok &&
          request['p_active'] is bool &&
          response['status'] ==
              (request['p_active'] == true ? 'active' : 'revoked'),
    // This existing caller uses action() for an audited access read.
    'admin_get_whatsapp_approval' =>
      request['p_user_id'] is String &&
          adminApprovalReadMatches(request['p_user_id'] as String, response),
    'admin_get_operator_approval_v1' =>
      request.length == 1 &&
          request['p_user_id'] is String &&
          adminOperatorApprovalReadMatches(
            request['p_user_id'] as String,
            response,
          ),
    _ => false,
  };
  if (!valid) {
    throw const FormatException(
      'The Admin action was not acknowledged. Refresh the record before trying again.',
    );
  }
}
