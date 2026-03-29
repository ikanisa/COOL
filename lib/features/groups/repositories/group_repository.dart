import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/group.dart';

class GroupRepository {
  GroupRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  SupabaseClient get client => _client;

  Future<List<Group>> getMyGroups(String userId, {String? country}) async {
    return const <Group>[];
  }

  Future<List<Group>> getPublicGroups(String searchQuery) async {
    return const <Group>[];
  }
}
