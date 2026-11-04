import 'collect_deployment_profile.dart';

const _managedProject = 'https://rrlduytparvsjfmegalh.supabase.co';

/// The profile is parsed and digest-bound by CollectSupabaseConfiguration.
/// A token claim must never choose the destination that receives that token.
bool collectMemberRealtimeOriginAllowed(
  String projectOrigin,
  CollectDeploymentProfile? profile,
) {
  if (profile == null) return projectOrigin == _managedProject;
  return profile.supabaseOrigin == projectOrigin &&
      (profile.mode == 'self_hosted' ||
          (profile.mode == 'managed' && projectOrigin == _managedProject));
}
