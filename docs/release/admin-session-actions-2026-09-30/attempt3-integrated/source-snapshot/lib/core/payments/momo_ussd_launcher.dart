import 'package:flutter/services.dart';

class MomoUssdLauncher {
  const MomoUssdLauncher();

  static const MethodChannel _channel = MethodChannel('collect/momo_ussd');

  Future<bool> launch({
    required String receiver,
    required int amountRwf,
    required String provider,
  }) async {
    if (!RegExp(r'^[0-9]{4,12}$').hasMatch(receiver) || amountRwf <= 0) {
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
    } on PlatformException catch (error) {
      throw StateError(
        error.message ?? 'MoMo USSD is unavailable on this device.',
      );
    }
  }
}
