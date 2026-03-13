import 'package:flutter/services.dart';

/// Native bridge for device-level settings that app permissions cannot open
/// through the standard app-settings entry point.
class DeviceSettingsService {
  DeviceSettingsService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('app.cool.mobile/device_settings');

  static final DeviceSettingsService instance = DeviceSettingsService();

  final MethodChannel _channel;

  Future<bool> openNfcSettings() async {
    try {
      final opened = await _channel.invokeMethod<bool>('openNfcSettings');
      return opened ?? false;
    } on PlatformException {
      return false;
    }
  }
}
