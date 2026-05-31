import 'package:flutter/services.dart';

class SmsAccessEnvelope {
  const SmsAccessEnvelope({
    required this.rawSender,
    required this.rawBody,
    required this.receivedAtDevice,
  });

  factory SmsAccessEnvelope.fromMap(Map<dynamic, dynamic> map) {
    return SmsAccessEnvelope(
      rawSender: (map['raw_sender'] as String?) ?? 'android_sms',
      rawBody: (map['raw_body'] as String?) ?? '',
      receivedAtDevice: (map['received_at_device'] as String?) ?? '',
    );
  }

  final String rawSender;
  final String rawBody;
  final String receivedAtDevice;
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

  Future<List<SmsAccessEnvelope>> drainPendingSms() async {
    try {
      final result = await _channel.invokeListMethod<Object?>(
        'drainPendingSms',
      );
      if (result == null) return const [];
      return result
          .whereType<Map<dynamic, dynamic>>()
          .map(SmsAccessEnvelope.fromMap)
          .where((item) => item.rawBody.trim().isNotEmpty)
          .toList(growable: false);
    } on MissingPluginException {
      return const [];
    }
  }
}
