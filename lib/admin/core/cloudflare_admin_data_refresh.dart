import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cloudflare_admin_session.dart';

/// Invalidates reads after an acknowledged change; holds no account data.
/// A new authority starts its own revision, never another operator's state.
final cloudflareAdminDataRevisionProvider = StateProvider<int>((ref) {
  ref.watch(
    cloudflareAdminSessionProvider.select(
      (session) => session.asData?.value?.authorityKey,
    ),
  );
  return 0;
});

void refreshCloudflareAdminData(WidgetRef ref) {
  final user = ref.read(cloudflareAdminSessionProvider).asData?.value;
  if (user == null || !user.expiresAt.isAfter(DateTime.now())) return;
  ref.read(cloudflareAdminDataRevisionProvider.notifier).state++;
}
