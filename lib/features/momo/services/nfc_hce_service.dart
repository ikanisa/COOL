import 'package:flutter/services.dart';

class NfcHceService {
  NfcHceService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('app.cool.mobile/nfc_hce');

  static final NfcHceService instance = NfcHceService();

  final MethodChannel _channel;

  Future<bool> isSupported() async {
    try {
      final supported = await _channel.invokeMethod<bool>('isSupported');
      return supported ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isPaymentRequestActive() async {
    try {
      final active = await _channel.invokeMethod<bool>(
        'isPaymentRequestActive',
      );
      return active ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<Uri?> getPaymentRequestUri() async {
    try {
      final rawUri = await _channel.invokeMethod<String>(
        'getPaymentRequestUri',
      );
      if (rawUri == null || rawUri.trim().isEmpty) {
        return null;
      }
      return Uri.tryParse(rawUri);
    } catch (_) {
      return null;
    }
  }

  Future<void> startPaymentRequest({required Uri uri}) {
    return _channel.invokeMethod<void>('startPaymentRequest', <String, dynamic>{
      'uri': uri.toString(),
    });
  }

  Future<void> stopPaymentRequest() {
    return _channel.invokeMethod<void>('stopPaymentRequest');
  }
}
