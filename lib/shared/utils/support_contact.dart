import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

const collectWhatsAppSupportPhone = '250795588248';

Uri collectWhatsAppSupportUri() =>
    Uri.https('wa.me', '/$collectWhatsAppSupportPhone');

void openCollectWhatsAppSupport() {
  unawaited(_openCollectWhatsAppSupport());
}

Future<void> _openCollectWhatsAppSupport() async {
  try {
    await launchUrl(
      collectWhatsAppSupportUri(),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    // Browser test shells and offline desktops may not have an external handler.
  }
}
