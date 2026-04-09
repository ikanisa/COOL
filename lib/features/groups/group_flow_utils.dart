import '../../core/config/deep_link_config.dart';
import '../../core/router/app_routes.dart';
import '../groups/models/group.dart';

bool groupHasContributionRoute(Group group) {
  final recipient = group.momoNumber?.trim() ?? '';
  return recipient.isNotEmpty;
}

String buildGroupContributionLocation(Group group) {
  final recipient = group.momoNumber?.trim() ?? '';
  if (recipient.isEmpty) {
    return AppRoutes.contributionCircles;
  }

  final recipientType = (group.momoRouteType?.trim().toLowerCase() ?? '')
          .contains('code')
      ? 'code'
      : 'phone_number';
  final queryParameters = <String, String>{
    'action': 'qr_pay',
    'recipient': recipient,
    'recipient_type': recipientType,
    'country': group.country.trim().isEmpty ? 'RW' : group.country.trim(),
    if ((group.id ?? '').isNotEmpty) 'reference': group.id!,
    if ((group.monthlyContribution ?? 0) > 0)
      'amount': '${group.monthlyContribution}',
  };

  return Uri(path: AppRoutes.momo, queryParameters: queryParameters).toString();
}

String? buildGroupInviteUrl(Group group) {
  final inviteCode = group.inviteCode?.trim().toUpperCase() ?? '';
  if (inviteCode.isEmpty) {
    return null;
  }
  return DeepLinkConfig.inviteUri(inviteCode).toString();
}
