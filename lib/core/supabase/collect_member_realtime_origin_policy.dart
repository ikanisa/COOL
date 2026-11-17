import 'collect_deployment_profile.dart';

const _managedProject = 'https://rrlduytparvsjfmegalh.supabase.co';

/// The profile is parsed and digest-bound by CollectSupabaseConfiguration.
/// A token claim must never choose the destination that receives that token.
bool collectMemberRealtimeOriginAllowed(
  String projectOrigin,
  CollectDeploymentProfile? profile,
) {
  if (profile == null) return projectOrigin == _managedProject;
  return profile.mode == 'managed' &&
      profile.supabaseOrigin == projectOrigin &&
      projectOrigin == _managedProject;
}
