import 'package:flutter/services.dart';

import '../data/exact_json_values.dart';

class MomoUssdLauncher {
  const MomoUssdLauncher();

  static const MethodChannel _channel = MethodChannel('collect/momo_ussd');

  /// Ask before obtaining a fresh payment review. Permission never opens USSD.
  Future<bool> ensurePermission() async {
    try {
      return await _channel.invokeMethod<bool>('ensurePermission') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> launch({
    required String receiver,
    required int amountRwf,
    required String provider,
  }) async {
    if (!RegExp(r'^[0-9]{4,12}$').hasMatch(receiver) ||
        amountRwf <= 0 ||
        amountRwf > maxExactJsonInteger) {
      throw const FormatException('Invalid MoMo USSD request.');
    }
    if (!const {'mtn_momo', 'airtel_money'}.contains(provider)) {
      throw const FormatException('Unsupported Rwanda MoMo provider.');
    }
    final code = provider == 'airtel_money'
        ? '*182*8*1#'
        : '*182**8*1*$receiver*$amountRwf#';
    try {
      return await _channel.invokeMethod<bool>('launch', {'ussd_code': code}) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      // A lost native reply can follow an attempted handoff. Keep the caller
      // in its conservative manual/confirmation state rather than retrying.
      return false;
    }
  }
}
