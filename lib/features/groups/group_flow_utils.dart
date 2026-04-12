import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/country_catalog.dart';
import '../../core/config/deep_link_config.dart';
import '../momo/providers/momo_service_provider.dart';
import '../groups/models/group.dart';

bool groupHasContributionRoute(Group group) {
  final recipient = group.momoNumber?.trim() ?? '';
  if (recipient.isEmpty) {
    return false;
  }
  final routeType = group.momoRouteType?.trim().toLowerCase() ?? '';
  if (routeType.isEmpty) {
    return true;
  }
  return routeType.contains('phone') || routeType.contains('code');
}

/// Launches the MoMo USSD payment flow for contributing to this group.
///
/// Uses the central MoMo service so group contributions follow the same
/// country-aware USSD rules, launch path, and observability as the rest of the
/// app.
Future<bool> launchGroupContribution(
  BuildContext context, {
  required Group group,
}) async {
  final recipient = group.momoNumber?.trim() ?? '';
  if (recipient.isEmpty) {
    return false;
  }

  final recipientType =
      (group.momoRouteType?.trim().toLowerCase() ?? '').contains('code')
      ? MomoRecipientType.code
      : MomoRecipientType.phoneNumber;

  final country = group.country.trim().isEmpty ? 'RW' : group.country.trim();
  final amount = (group.monthlyContribution ?? 0) > 0
      ? group.monthlyContribution!
      : null;

  try {
    final momoService = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(momoServiceProvider);
    await momoService.initiatePaymentUSSD(
      amount,
      recipientMomo: recipient,
      recipientType: recipientType,
      countryCode: country,
      reference: group.id == null || group.id!.trim().isEmpty
          ? 'GROUP-CONTRIBUTION'
          : 'GROUP-${group.id!.trim()}',
    );
    return true;
  } catch (_) {
    return false;
  }
}

String? buildGroupInviteUrl(Group group) {
  final inviteCode = group.inviteCode?.trim().toUpperCase() ?? '';
  if (inviteCode.isEmpty) {
    return null;
  }
  return DeepLinkConfig.inviteUri(inviteCode).toString();
}
