import 'package:flutter/services.dart';

class ReceiverSmsEnvelope {
  const ReceiverSmsEnvelope({
    required this.rawSender,
    required this.rawBody,
    required this.receivedAtDevice,
  });

  factory ReceiverSmsEnvelope.fromMap(Map<dynamic, dynamic> map) {
    return ReceiverSmsEnvelope(
      rawSender: (map['raw_sender'] as String?) ?? 'android_sms',
      rawBody: (map['raw_body'] as String?) ?? '',
      receivedAtDevice: (map['received_at_device'] as String?) ?? '',
    );
  }

  final String rawSender;
  final String rawBody;
  final String receivedAtDevice;
}

class ReceiverModeChannel {
  const ReceiverModeChannel();

  static const MethodChannel _channel = MethodChannel('collect/receiver_mode');

  Future<void> setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setEnabled', {'enabled': enabled});
    } on MissingPluginException {
      return;
    }
  }

  Future<bool> isEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<List<ReceiverSmsEnvelope>> drainPendingSms() async {
    try {
      final result = await _channel.invokeListMethod<Object?>(
        'drainPendingSms',
      );
      if (result == null) return const [];
      return result
          .whereType<Map<dynamic, dynamic>>()
          .map(ReceiverSmsEnvelope.fromMap)
          .where((item) => item.rawBody.trim().isNotEmpty)
          .toList(growable: false);
    } on MissingPluginException {
      return const [];
    }
  }
}
