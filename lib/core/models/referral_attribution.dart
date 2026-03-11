class ReferralAttribution {
  const ReferralAttribution({
    required this.inviteId,
    required this.route,
    required this.queryParameters,
    this.campaignId,
    this.inviteCode,
    this.openedLogged = false,
  });

  factory ReferralAttribution.fromUri(Uri uri, {required String route}) {
    return ReferralAttribution(
      inviteId: uri.queryParameters['ri']!.trim(),
      route: route,
      queryParameters: Map<String, String>.unmodifiable(uri.queryParameters),
      campaignId: uri.queryParameters['campaign']?.trim(),
      inviteCode: uri.queryParameters['code']?.trim(),
    );
  }

  final String inviteId;
  final String route;
  final Map<String, String> queryParameters;
  final String? campaignId;
  final String? inviteCode;
  final bool openedLogged;

  ReferralAttribution copyWith({
    String? route,
    Map<String, String>? queryParameters,
    String? campaignId,
    String? inviteCode,
    bool? openedLogged,
  }) {
    return ReferralAttribution(
      inviteId: inviteId,
      route: route ?? this.route,
      queryParameters: queryParameters ?? this.queryParameters,
      campaignId: campaignId ?? this.campaignId,
      inviteCode: inviteCode ?? this.inviteCode,
      openedLogged: openedLogged ?? this.openedLogged,
    );
  }
}

class ReferralInviteLink {
  const ReferralInviteLink({
    required this.inviteId,
    required this.uri,
    this.campaignId,
  });

  final String inviteId;
  final Uri uri;
  final String? campaignId;
}
