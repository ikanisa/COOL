import 'package:flutter/services.dart';

class SmsAccessEnvelope {
  const SmsAccessEnvelope({
    required this.id,
    required this.rawSender,
    required this.rawBody,
    required this.receivedAtDevice,
  });

  factory SmsAccessEnvelope.fromMap(Map<dynamic, dynamic> map) {
    return SmsAccessEnvelope(
      id: (map['id'] as String?) ?? '',
      rawSender: (map['raw_sender'] as String?) ?? 'android_sms',
      rawBody: (map['raw_body'] as String?) ?? '',
      receivedAtDevice: (map['received_at_device'] as String?) ?? '',
    );
  }

  final String id;
  final String rawSender;
  final String rawBody;
  final String receivedAtDevice;
}

class SmsAccessStatus {
  const SmsAccessStatus({
    required this.supported,
    required this.declared,
    required this.enabled,
    required this.granted,
    required this.requestedBefore,
    required this.shouldShowRationale,
    required this.permanentlyDenied,
  });

  const SmsAccessStatus.unavailable()
    : supported = false,
      declared = false,
      enabled = false,
      granted = false,
      requestedBefore = false,
      shouldShowRationale = false,
      permanentlyDenied = false;

  factory SmsAccessStatus.fromMap(Map<dynamic, dynamic> map) {
    bool value(String key) => map[key] == true;
    return SmsAccessStatus(
      supported: value('supported'),
      declared: value('declared'),
      enabled: value('enabled'),
      granted: value('granted'),
      requestedBefore: value('requested_before'),
      shouldShowRationale: value('should_show_rationale'),
      permanentlyDenied: value('permanently_denied'),
    );
  }

  final bool supported;
  final bool declared;
  final bool enabled;
  final bool granted;
  final bool requestedBefore;
  final bool shouldShowRationale;
  final bool permanentlyDenied;
}

class SmsAccessChannel {
  const SmsAccessChannel();

  static const MethodChannel _channel = MethodChannel('collect/sms_access');

  Future<bool> setEnabled(bool enabled) async {
    try {
      return await _channel.invokeMethod<bool>('setEnabled', {
            'enabled': enabled,
          }) ??
          false;
    } on MissingPluginException {
      return !enabled;
    } on PlatformException {
      return !enabled;
    }
  }

  Future<bool> isEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<SmsAccessStatus> status() async {
    try {
      final result = await _channel.invokeMapMethod<dynamic, dynamic>('status');
      return result == null
          ? const SmsAccessStatus.unavailable()
          : SmsAccessStatus.fromMap(result);
    } on MissingPluginException {
      return const SmsAccessStatus.unavailable();
    } on PlatformException catch (error) {
      final details = error.details;
      return details is Map
          ? SmsAccessStatus.fromMap(details)
          : const SmsAccessStatus.unavailable();
    }
  }

  Future<List<SmsAccessEnvelope>> readPendingSms() async {
    try {
      final result = await _channel.invokeListMethod<Object?>('readPendingSms');
      if (result == null) return const [];
      return result
          .whereType<Map<dynamic, dynamic>>()
          .map(SmsAccessEnvelope.fromMap)
          .where(
            (item) =>
                item.id.trim().isNotEmpty && item.rawBody.trim().isNotEmpty,
          )
          .toList(growable: false);
    } on MissingPluginException {
      return const [];
    }
  }

  Future<bool> acknowledgePendingSms(Iterable<String> ids) async {
    final cleanIds = ids.map((id) => id.trim()).where((id) => id.isNotEmpty);
    if (cleanIds.isEmpty) return true;
    try {
      return await _channel.invokeMethod<bool>('ackPendingSms', {
            'ids': cleanIds.toList(growable: false),
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> openAppSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openAppSettings') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
