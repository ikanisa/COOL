import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/supabase_client_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/group.dart';
import '../repositories/group_repository.dart';

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return GroupRepository(client: ref.read(supabaseClientProvider));
});

final myGroupsProvider = FutureProvider<List<Group>>((ref) async {
  final authState = ref.watch(authProvider);
  final repository = ref.read(groupRepositoryProvider);
  return repository.getMyGroups(
    authState.user?.id ?? authState.session?.user.id ?? '',
    country: authState.user?.country,
  );
});

final publicGroupsProvider = FutureProvider<List<Group>>((ref) async {
  final repository = ref.read(groupRepositoryProvider);
  return repository.getPublicGroups('');
});
