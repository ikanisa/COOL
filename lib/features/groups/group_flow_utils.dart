import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/deep_link_config.dart';
import '../groups/models/group.dart';

bool groupHasContributionRoute(Group group) {
  final recipient = group.momoNumber?.trim() ?? '';
  return recipient.isNotEmpty;
}

/// Launches the MoMo USSD payment flow for contributing to this group.
///
/// For Rwanda: dials *182*8*1*{code}# (merchant code) or
/// *182*1*1*{phone}*{amount}# (P2P transfer).
/// Returns true if the USSD was successfully launched.
Future<bool> launchGroupContribution(
  BuildContext context, {
  required Group group,
}) async {
  final recipient = group.momoNumber?.trim() ?? '';
  if (recipient.isEmpty) {
    return false;
  }

  final recipientType = (group.momoRouteType?.trim().toLowerCase() ?? '')
          .contains('code')
      ? 'code'
      : 'phone_number';

  final country = group.country.trim().isEmpty ? 'RW' : group.country.trim();
  final amount = (group.monthlyContribution ?? 0) > 0
      ? group.monthlyContribution!
      : null;

  // Build USSD string based on payment route type
  String ussdCode;
  if (country == 'RW') {
    if (recipientType == 'code') {
      // MTN MoMo merchant payment: *182*8*1*{code}#
      ussdCode = '*182*8*1*$recipient%23';
    } else {
      // MTN MoMo P2P: *182*1*1*{phone}*{amount}#
      if (amount != null && amount > 0) {
        ussdCode = '*182*1*1*$recipient*$amount%23';
      } else {
        ussdCode = '*182*1*1*$recipient%23';
      }
    }
  } else {
    // Fallback — just dial the number
    ussdCode = recipient;
  }

  final uri = Uri.parse('tel:$ussdCode');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
    return true;
  }
  return false;
}

String? buildGroupInviteUrl(Group group) {
  final inviteCode = group.inviteCode?.trim().toUpperCase() ?? '';
  if (inviteCode.isEmpty) {
    return null;
  }
  return DeepLinkConfig.inviteUri(inviteCode).toString();
}
