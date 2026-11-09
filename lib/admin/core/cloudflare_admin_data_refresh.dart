import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cloudflare_admin_session.dart';

/// Invalidates mounted reads only after an acknowledged change or a verified
/// original receipt. A new authority never inherits the previous revision.
final cloudflareAdminDataRevisionProvider = StateProvider<int>((ref) {
  ref.watch(
    cloudflareAdminSessionProvider.select(
      (session) => session.asData?.value?.authorityKey,
    ),
  );
  return 0;
});

/// A response is current only for the same session generation, including
/// failed authority checks and a switch away and back to the same account.
bool cloudflareAdminAuthorityIsCurrent(WidgetRef ref, Object fence) {
  final session = ref.read(cloudflareAdminSessionProvider.notifier);
  final user = ref.read(cloudflareAdminSessionProvider).asData?.value;
  return user != null &&
      user.expiresAt.isAfter(DateTime.now()) &&
      session.authorityFence == fence;
}

void refreshCloudflareAdminData(WidgetRef ref, Object fence) {
  if (!cloudflareAdminAuthorityIsCurrent(ref, fence)) return;
  ref.read(cloudflareAdminDataRevisionProvider.notifier).state++;
}
