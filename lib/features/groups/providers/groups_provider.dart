import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/supabase_client_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/group_access_snapshot.dart';
import '../models/group.dart';
import '../models/group_invite_preview.dart';
import '../repositories/group_repository.dart';

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return GroupRepository(client: ref.read(supabaseClientProvider));
});

final groupsRefreshTickProvider = StateProvider<int>((ref) => 0);

final myGroupsProvider = FutureProvider<List<Group>>((ref) async {
  ref.watch(groupsRefreshTickProvider);
  final authState = ref.watch(authProvider);
  final repository = ref.read(groupRepositoryProvider);
  return repository.getMyGroups(
    authState.user?.id ?? authState.session?.user.id ?? '',
    country: authState.user?.country,
  );
});

final myGroupIdsProvider = Provider<Set<String>>((ref) {
  final groups = ref.watch(myGroupsProvider).valueOrNull ?? const <Group>[];
  return groups
      .map((group) => group.id ?? '')
      .where((id) => id.isNotEmpty)
      .toSet();
});

final publicGroupsSearchProvider =
    FutureProvider.family<List<Group>, String>((ref, searchQuery) async {
      ref.watch(groupsRefreshTickProvider);
      final authState = ref.watch(authProvider);
      final repository = ref.read(groupRepositoryProvider);
      return repository.getPublicGroups(
        searchQuery,
        country: authState.user?.country,
      );
    });

final publicGroupsProvider = FutureProvider<List<Group>>((ref) async {
  ref.watch(groupsRefreshTickProvider);
  final authState = ref.watch(authProvider);
  final repository = ref.read(groupRepositoryProvider);
  return repository.getPublicGroups(
    '',
    country: authState.user?.country,
  );
});

final groupDetailProvider = FutureProvider.family<Group?, String>((
  ref,
  groupId,
) async {
  ref.watch(groupsRefreshTickProvider);
  final repository = ref.read(groupRepositoryProvider);
  return repository.getGroupById(groupId);
});

final groupAccessProvider =
    FutureProvider.family<GroupAccessSnapshot?, String>((ref, groupId) async {
      ref.watch(groupsRefreshTickProvider);
      final repository = ref.read(groupRepositoryProvider);
      return repository.getGroupAccessSnapshot(groupId);
    });

final groupInvitePreviewProvider =
    FutureProvider.family<GroupInvitePreview?, String>((ref, inviteCode) async {
      ref.watch(groupsRefreshTickProvider);
      final repository = ref.read(groupRepositoryProvider);
      return repository.getInvitePreview(inviteCode);
    });

final groupActionsProvider = Provider<GroupRepository>((ref) {
  final repository = ref.read(groupRepositoryProvider);
  return repository;
});
