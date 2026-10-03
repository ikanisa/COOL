import 'package:flutter/services.dart';

class GatewayRecoveryStatus {
  const GatewayRecoveryStatus({
    required this.operation,
    required this.state,
    required this.phase,
    required this.completedFiles,
    required this.manifestSha256,
    required this.files,
    required this.keyValidated,
    required this.inactive,
    required this.requiresReEnrollment,
    required this.reasonCode,
  });

  factory GatewayRecoveryStatus.fromMap(Map<Object?, Object?> map) {
    const keys = {
      'contract_version',
      'operation',
      'state',
      'phase',
      'completed_files',
      'manifest_sha256',
      'files',
      'key_validated',
      'inactive',
      'requires_re_enrollment',
      'reason_code',
    };
    Never invalid() => throw const FormatException('gateway_recovery_invalid');
    if (map.length != keys.length ||
        !keys.every(map.containsKey) ||
        map['contract_version'] != 1) {
      invalid();
    }
    final operation = map['operation'];
    final state = map['state'];
    final phase = map['phase'];
    final count = map['completed_files'];
    final sha = map['manifest_sha256'];
    final files = map['files'];
    final key = map['key_validated'];
    final inactive = map['inactive'];
    final reEnrollment = map['requires_re_enrollment'];
    final reason = map['reason_code'];
    if (!{'none', 'export', 'restore'}.contains(operation) ||
        !{
          'idle',
          'working',
          'complete',
          'cancelled',
          'failed',
        }.contains(state) ||
        !{
          'idle',
          'preparing',
          'picker',
          'snapshot',
          'writing',
          'verifying',
          'reading',
          'validating',
          'complete',
          'cancelled',
          'failed',
        }.contains(phase) ||
        count is! int ||
        count < 0 ||
        count > 0x7fffffffffffffff ||
        (sha != null &&
            (sha is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha))) ||
        (files != null &&
            (files is! int || files < count || files > 0x7fffffffffffffff)) ||
        (key != null && key is! bool) ||
        inactive is! bool ||
        reEnrollment is! bool ||
        inactive != (operation == 'restore') ||
        reEnrollment != inactive ||
        (reason != null &&
            (reason is! String ||
                !RegExp(r'^gateway_[a-z_]{1,80}$').hasMatch(reason)))) {
      invalid();
    }
    if ((state == 'idle') != (operation == 'none') ||
        (state == 'idle' && phase != 'idle') ||
        (state == 'working' &&
            {'idle', 'complete', 'cancelled', 'failed'}.contains(phase)) ||
        (state == 'complete' &&
            (phase != 'complete' ||
                sha == null ||
                files == null ||
                files != count ||
                reason != null ||
                (operation == 'restore' && key == null))) ||
        ((state == 'failed' || state == 'cancelled') &&
            (phase != state || reason == null)) ||
        (operation != 'restore' && key != null)) {
      invalid();
    }
    return GatewayRecoveryStatus(
      operation: operation as String,
      state: state as String,
      phase: phase as String,
      completedFiles: count,
      manifestSha256: sha as String?,
      files: files as int?,
      keyValidated: key as bool?,
      inactive: inactive,
      requiresReEnrollment: reEnrollment,
      reasonCode: reason as String?,
    );
  }
  final String operation, state, phase;
  final int completedFiles;
  final String? manifestSha256, reasonCode;
  final int? files;
  final bool? keyValidated;
  final bool inactive, requiresReEnrollment;
  bool get working => state == 'working';
}

abstract interface class GatewayRecoveryPlatform {
  Future<GatewayRecoveryStatus> status();
  Future<GatewayRecoveryStatus> export();
  Future<GatewayRecoveryStatus> restore(String trustedManifestSha256);
  Future<GatewayRecoveryStatus> cancel();
}

class NativeGatewayRecoveryPlatform implements GatewayRecoveryPlatform {
  const NativeGatewayRecoveryPlatform();
  static const _channel = MethodChannel('collect/gateway.recovery.v1');
  Future<GatewayRecoveryStatus> _request(
    String method, [
    Map<String, String>? args,
  ]) async {
    // Long maintenance operations finish through their actual native result.
    // Cancellation/status stay independent and never automatically repeat work.
    final future = _channel.invokeMapMethod<Object?, Object?>(method, args);
    final map = method == 'status' || method == 'cancel'
        ? await future.timeout(const Duration(seconds: 10))
        : await future;
    if (map == null) throw const FormatException('gateway_recovery_invalid');
    final result = GatewayRecoveryStatus.fromMap(map);
    if ((method == 'export' || method == 'restore') &&
        result.operation != method) {
      throw const FormatException('gateway_recovery_invalid');
    }
    return result;
  }

  @override
  Future<GatewayRecoveryStatus> status() => _request('status');
  @override
  Future<GatewayRecoveryStatus> export() => _request('export');
  @override
  Future<GatewayRecoveryStatus> restore(String trustedManifestSha256) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(trustedManifestSha256)) {
      throw const FormatException('gateway_recovery_invalid');
    }
    return _request('restore', {'manifest_sha256': trustedManifestSha256});
  }

  @override
  Future<GatewayRecoveryStatus> cancel() => _request('cancel');
}
