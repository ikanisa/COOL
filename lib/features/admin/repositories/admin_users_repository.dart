import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_repository_helpers.dart';
import 'admin_user_row_normalizer.dart';

/// Repository for admin user inventory, profile updates, and mock cleanup.
class AdminUsersRepository with AdminRepositoryHelpers {
  AdminUsersRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  @override
  SupabaseClient get client => _client;

  Future<List<Map<String, dynamic>>> fetchUsers() async {
    final data = await _client
        .from('users')
        .select(
          'id, public_user_id, full_name, phone, country, language_code, '
          'momo_provider, is_admin, '
          'created_at, is_mock, mock_batch',
        )
        .order('is_mock', ascending: false)
        .order('created_at', ascending: false);
    return asListOfMaps(
      data,
    ).map(normalizeAdminUserRowForAppMarket).toList(growable: false);
  }

  Future<Map<String, dynamic>> purgeMockBatch(String batch) async {
    final data = await _client.rpc(
      'purge_mock_batch',
      params: <String, dynamic>{'p_mock_batch': batch},
    );
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    throw StateError('Expected purge_mock_batch to return a JSON object.');
  }

  Future<void> toggleUserAdmin(String userId, bool isAdmin) async {
    await _client
        .from('users')
        .update(<String, dynamic>{'is_admin': isAdmin})
        .eq('id', userId);
  }

  Future<void> updateUserFields(
    String userId,
    Map<String, dynamic> fields,
  ) async {
    await _client.from('users').update(fields).eq('id', userId);
  }
}
