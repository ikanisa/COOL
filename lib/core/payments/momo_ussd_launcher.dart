import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class MomoUssdLauncher {
  MomoUssdLauncher({MethodChannel? androidChannel})
    : _androidChannel =
          androidChannel ?? const MethodChannel('collect/momo_ussd');

  final MethodChannel _androidChannel;

  Future<bool> launch(Uri uri) async {
    if (uri.scheme != 'tel') {
      throw ArgumentError.value(uri, 'uri', 'MoMo USSD must use tel:');
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return await _androidChannel.invokeMethod<bool>('launch', {
            'uri': uri.toString(),
          }) ??
          false;
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
