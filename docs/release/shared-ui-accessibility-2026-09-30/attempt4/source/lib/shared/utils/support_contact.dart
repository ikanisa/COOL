import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

import '../models/collect_models.dart';

Uri collectWhatsAppSupportUri({
  String phone = collectDefaultWhatsAppSupportPhone,
}) => Uri.https('wa.me', '/$phone');

void openCollectWhatsAppSupport({
  String phone = collectDefaultWhatsAppSupportPhone,
}) {
  unawaited(_openCollectWhatsAppSupport(phone: phone));
}

Future<void> _openCollectWhatsAppSupport({required String phone}) async {
  try {
    await launchUrl(
      collectWhatsAppSupportUri(phone: phone),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    // Browser test shells and offline desktops may not have an external handler.
  }
}
