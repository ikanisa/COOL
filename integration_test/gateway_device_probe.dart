import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:collect_app/gateway/gateway_platform.dart';

/// The physical smoke target deliberately has no backend or sender operations.
/// It creates/reads only the app's public device identity and local observation.
Future<Map<String, Object>> observeGatewayWithoutSending(
  GatewayPlatform platform,
) async {
  final initial = await platform.initialize();
  if (initial.configured || !initial.paused) {
    throw const FormatException('gateway_probe_requires_offline_paused_build');
  }
  final first = await platform.identity();
  final second = await platform.identity();
  const keys = {
    'contract_version',
    'installation_id',
    'key_sha256',
    'signing_certificate_sha256',
    'public_key_spki_base64',
  };
  final uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  final fingerprint = RegExp(r'^[0-9a-f]{64}$');
  if (first.length != keys.length ||
      second.length != keys.length ||
      !keys.every(first.containsKey) ||
      !keys.every(second.containsKey) ||
      first['contract_version'] != 1 ||
      first['installation_id'] is! String ||
      !uuid.hasMatch(first['installation_id']! as String) ||
      first['key_sha256'] is! String ||
      !fingerprint.hasMatch(first['key_sha256']! as String) ||
      first['signing_certificate_sha256'] is! String ||
      !fingerprint.hasMatch(first['signing_certificate_sha256']! as String) ||
      first['public_key_spki_base64'] is! String ||
      !keys.every((key) => first[key] == second[key])) {
    throw const FormatException('gateway_probe_identity_invalid');
  }
  final encodedKey = first['public_key_spki_base64']! as String;
  if (encodedKey.length > 2048) {
    throw const FormatException('gateway_probe_identity_invalid');
  }
  final List<int> publicKey;
  try {
    publicKey = base64Decode(encodedKey);
  } on FormatException {
    throw const FormatException('gateway_probe_identity_invalid');
  }
  if (publicKey.isEmpty ||
      publicKey.length > 1024 ||
      sha256.convert(publicKey).toString() != first['key_sha256']) {
    throw const FormatException('gateway_probe_identity_invalid');
  }
  final current = await platform.refresh();
  if (current.configured ||
      !current.paused ||
      current.pendingAttempts != initial.pendingAttempts ||
      current.frameworkSentAttempts != initial.frameworkSentAttempts ||
      current.deliveryCallbacksObserved != initial.deliveryCallbacksObserved ||
      current.enrollment != initial.enrollment) {
    throw const FormatException('gateway_probe_local_state_changed');
  }
  return {
    'kind': 'native_gateway_no_send_observation',
    'observed_at_utc': DateTime.now().toUtc().toIso8601String(),
    'public_identity_stable_in_process': true,
    'public_key_hash_matches': true,
    'signing_certificate_sha256':
        first['signing_certificate_sha256']! as String,
    'configured': current.configured,
    'emergency_paused': current.paused,
    'enrollment': current.enrollment.name,
    'send_sms_permission': current.sendPermission,
    'read_phone_state_permission': current.phonePermission,
    'network_connected': current.networkConnected,
    'network_validated': current.networkValidated,
    'sim_ready': current.simReady,
    'telephony_in_service': current.telephonyInService,
    'subscription_selected': current.subscriptionSelected,
    'outcome_unknown_attempts': current.pendingAttempts,
    'framework_sent_attempts': current.frameworkSentAttempts,
    'delivery_callback_attempts': current.deliveryCallbacksObserved,
    'backend_calls': 0,
    'sms_invocations': 0,
    'physical_acceptance': false,
    'carrier_delivery_acceptance': false,
  };
}
