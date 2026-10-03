import 'package:flutter/services.dart';

enum GatewayEnrollment {
  notEnrolled,
  pending,
  active,
  paused,
  revoked,
  unknown,
}

class GatewaySnapshot {
  const GatewaySnapshot({
    required this.enrollment,
    required this.paused,
    required this.configured,
    required this.sendPermission,
    required this.phonePermission,
    required this.networkConnected,
    required this.networkValidated,
    required this.simReady,
    required this.telephonyInService,
    required this.subscriptionSelected,
    required this.pendingAttempts,
    required this.frameworkSentAttempts,
    required this.deliveryCallbacksObserved,
    required this.reasonCode,
  });

  factory GatewaySnapshot.fromMap(Map<Object?, Object?> value) {
    const keys = {
      'enrollment',
      'emergency_paused',
      'configured',
      'send_sms_permission',
      'read_phone_state_permission',
      'network_connected',
      'network_validated',
      'sim_ready',
      'telephony_in_service',
      'subscription_selected',
      'outcome_unknown_attempts',
      'framework_sent_attempts',
      'delivery_callback_attempts',
      'reason_code',
    };
    if (value.length != keys.length || !keys.every(value.containsKey)) {
      throw const FormatException('gateway_status_invalid');
    }
    bool flag(String name) {
      final result = value[name];
      if (result is! bool) {
        throw const FormatException('gateway_status_invalid');
      }
      return result;
    }

    int count(String name) {
      final result = value[name];
      if (result is! int || result < 0 || result > 100) {
        throw const FormatException('gateway_status_invalid');
      }
      return result;
    }

    const states = {
      'not_enrolled': GatewayEnrollment.notEnrolled,
      'pending': GatewayEnrollment.pending,
      'active': GatewayEnrollment.active,
      'paused': GatewayEnrollment.paused,
      'revoked': GatewayEnrollment.revoked,
      'unknown': GatewayEnrollment.unknown,
    };
    final state = states[value['enrollment']];
    final reason = value['reason_code'];
    if (state == null ||
        reason is! String ||
        !RegExp(r'^gateway_[a-z_]{1,80}$').hasMatch(reason)) {
      throw const FormatException('gateway_status_invalid');
    }
    final snapshot = GatewaySnapshot(
      enrollment: state,
      paused: flag('emergency_paused'),
      configured: flag('configured'),
      sendPermission: flag('send_sms_permission'),
      phonePermission: flag('read_phone_state_permission'),
      networkConnected: flag('network_connected'),
      networkValidated: flag('network_validated'),
      simReady: flag('sim_ready'),
      telephonyInService: flag('telephony_in_service'),
      subscriptionSelected: flag('subscription_selected'),
      pendingAttempts: count('outcome_unknown_attempts'),
      frameworkSentAttempts: count('framework_sent_attempts'),
      deliveryCallbacksObserved: count('delivery_callback_attempts'),
      reasonCode: reason,
    );
    if (snapshot.deliveryCallbacksObserved > snapshot.frameworkSentAttempts ||
        snapshot.frameworkSentAttempts + snapshot.pendingAttempts > 100 ||
        (snapshot.networkValidated && !snapshot.networkConnected) ||
        (snapshot.simReady && !snapshot.phonePermission) ||
        (snapshot.telephonyInService && !snapshot.phonePermission)) {
      throw const FormatException('gateway_status_invalid');
    }
    return snapshot;
  }

  final GatewayEnrollment enrollment;
  final bool paused, configured, sendPermission, phonePermission;
  final bool networkConnected, networkValidated, simReady;
  final bool telephonyInService, subscriptionSelected;
  final int pendingAttempts, frameworkSentAttempts, deliveryCallbacksObserved;
  final String reasonCode;
}

abstract interface class GatewayPlatform {
  Future<GatewaySnapshot> initialize();
  Future<GatewaySnapshot> refresh();
  Future<GatewaySnapshot> pause();
  Future<GatewaySnapshot> requestPermissions();
  Future<GatewaySnapshot> heartbeat();
  Future<GatewaySnapshot> reconcile();
  Future<Map<Object?, Object?>> identity();
  Future<GatewaySnapshot> provisionEnrollment(Map<String, Object?> document);
}

class NativeGatewayPlatform implements GatewayPlatform {
  const NativeGatewayPlatform();
  static const _channel = MethodChannel('collect/gateway.v1');

  Future<GatewaySnapshot> _request(
    String name, [
    Map<String, Object?>? document,
  ]) async {
    final result = await _channel
        .invokeMapMethod<Object?, Object?>(name, document)
        .timeout(Duration(seconds: name == 'reconcile' ? 65 : 20));
    if (result == null) throw const FormatException('gateway_status_invalid');
    return GatewaySnapshot.fromMap(result);
  }

  @override
  Future<GatewaySnapshot> initialize() => _request('initialize');
  @override
  Future<GatewaySnapshot> refresh() => _request('status');
  @override
  Future<GatewaySnapshot> pause() => _request('pause');
  @override
  Future<GatewaySnapshot> requestPermissions() =>
      _request('requestPermissions');
  @override
  Future<GatewaySnapshot> heartbeat() => _request('heartbeat');
  @override
  Future<GatewaySnapshot> reconcile() => _request('reconcile');
  @override
  Future<Map<Object?, Object?>> identity() async =>
      await _channel
          .invokeMapMethod<Object?, Object?>('identity')
          .timeout(const Duration(seconds: 20)) ??
      const {};
  @override
  Future<GatewaySnapshot> provisionEnrollment(Map<String, Object?> document) =>
      _request('provisionEnrollment', document);
}
