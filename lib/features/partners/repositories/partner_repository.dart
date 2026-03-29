import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/partner.dart';

class PartnerRepository {
  PartnerRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  SupabaseClient get client => _client;

  Future<List<Partner>> fetchAll() async {
    return const <Partner>[];
  }

  Future<Partner?> fetchById(String id) async {
    final normalized = id.trim();
    if (normalized.isEmpty) {
      return null;
    }

    final partners = await fetchAll();
    for (final partner in partners) {
      if (partner.id == normalized) {
        return partner;
      }
    }
    return null;
  }
}
