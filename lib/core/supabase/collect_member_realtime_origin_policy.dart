import 'collect_deployment_profile.dart';

/// The profile is parsed and digest-bound by CollectSupabaseConfiguration.
/// A token claim must never choose the destination that receives that token.
bool collectMemberRealtimeOriginAllowed(
  String projectOrigin,
  CollectDeploymentProfile? profile,
) {
  return projectOrigin == CollectDeploymentProfile.managedProject &&
      (profile == null ||
          (profile.mode == 'managed' &&
              profile.supabaseOrigin == projectOrigin));
}
