part 'public_page_content.dart';
part 'public_marketing_page_content.dart';
part 'public_capability_content.dart';
part 'public_policy_page_content.dart';

/// Public product facts describe source-observed capabilities. Publishing or
/// approving a service requires evidence outside this engineering adapter.
class CollectPublicCapabilityData {
  const CollectPublicCapabilityData({
    required this.label,
    required this.summary,
    required this.region,
    required this.ownerApproved,
    required this.availability,
    required this.actionLabel,
    required this.actionHref,
    required this.fallbackLabel,
    required this.fallbackHref,
  });

  final String label;
  final String summary;
  final String region;
  final bool ownerApproved;
  final Map<String, String> availability;
  final String actionLabel;
  final String actionHref;
  final String fallbackLabel;
  final String fallbackHref;

  bool supportsSourceAction({
    required String region,
    required String platform,
  }) {
    if (region != this.region) return false;
    final state = availability[platform];
    return state == 'supported' || state == 'assisted';
  }

  bool hasApprovedAvailability({
    required String region,
    required String platform,
  }) =>
      ownerApproved && supportsSourceAction(region: region, platform: platform);

  Uri nextAction({required String region, required String platform}) =>
      Uri.parse(
        supportsSourceAction(region: region, platform: platform)
            ? actionHref
            : fallbackHref,
      );
}

/// A runtime configuration may choose a download URL, but it cannot silently
/// advertise a new product/platform outside the current capability register.
({String label, String href}) collectPublicDownloadAction(
  String configuredUrl,
) {
  final capability = collectPublicCapabilities['group_records']!;
  if (configuredUrl == capability.actionHref &&
      capability.supportsSourceAction(region: 'RW', platform: 'android')) {
    return (label: capability.actionLabel, href: configuredUrl);
  }
  return (label: capability.fallbackLabel, href: capability.fallbackHref);
}
