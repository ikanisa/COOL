import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/widgets/cool_toast.dart';

class WhatsAppContactService {
  WhatsAppContactService._();

  static Future<void> openChat(
    BuildContext context, {
    required String phoneNumber,
    String? message,
    String unavailableMessage = 'WhatsApp is not available on this device.',
    String failureMessage = 'Could not open WhatsApp right now.',
  }) async {
    final normalized = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final query = message == null || message.trim().isEmpty
        ? ''
        : '?text=${Uri.encodeComponent(message.trim())}';
    final uri = Uri.parse('https://wa.me/$normalized$query');

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        CoolToast.error(context, unavailableMessage);
      }
    } catch (_) {
      if (context.mounted) {
        CoolToast.error(context, failureMessage);
      }
    }
  }
}
