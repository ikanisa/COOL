import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_market.dart';
import '../models/rs_models.dart';
import '../rayon_identity.dart' as rayon_identity;
import '../rs_membership_package.dart';
import '../rayon_payment.dart';

class RayonSportsMembershipRepository {
  RayonSportsMembershipRepository({
    required SupabaseClient client,
    required String Function(
      String? userId, {
      String? seededDisplayName,
      String fallback,
    })
    displayNameForUser,
    required RsJsonMap Function(RsJsonMap row) withResolvedDisplayName,
  }) : _client = client,
       _displayNameForUser = displayNameForUser,
       _withResolvedDisplayName = withResolvedDisplayName;

  final SupabaseClient _client;
  final String Function(
    String? userId, {
    String? seededDisplayName,
    String fallback,
  })
  _displayNameForUser;
  final RsJsonMap Function(RsJsonMap row) _withResolvedDisplayName;

  PartnerPaymentRoute? _cachedPaymentRoute;

  Future<RsJsonMap> resolvePartnerSummary() async {
    try {
      final slugRow = await _client
          .from('partners')
          .select('id, slug, name, country')
          .eq('slug', 'rayon-sports')
          .limit(1)
          .maybeSingle();
      final slugPartner = _asMapOrNull(slugRow);
      if (slugPartner != null) {
        final slugId = slugPartner['id']?.toString().trim() ?? '';
        if (slugId.isNotEmpty) {
          return slugPartner;
        }
      }
    } on PostgrestException catch (_) {
      // Older environments may not have the slug column yet.
    }

    final exactMatches = _asListOfMaps(
      await _client
          .from('partners')
          .select('id, slug, name, country')
          .inFilter('name', rayon_identity.rayonSportsPartnerLookupNames),
    );
    final preferredMatch = _pickPreferredRayonPartner(exactMatches);
    if (preferredMatch != null) {
      return preferredMatch;
    }

    final fallbackRow = await _client
        .from('partners')
        .select('id, slug, name, country')
        .ilike('name', 'Rayon Sports%')
        .maybeSingle();
    return _asMapOrNull(fallbackRow) ?? const <String, Object?>{};
  }

  Future<String?> resolvePartnerId() async {
    final partner = await resolvePartnerSummary();
    final partnerId = partner['id']?.toString().trim();
    if (partnerId == null || partnerId.isEmpty) {
      return null;
    }
    return partnerId;
  }

  Future<void> joinClub({
    required String clubId,
    required String userId,
  }) async {
    await _client.from('rs_fan_club_members').upsert(<String, Object?>{
      'club_id': clubId,
      'user_id': userId,
    }, onConflict: 'club_id,user_id');
  }

  Future<void> leaveClub({
    required String clubId,
    required String userId,
  }) async {
    await _client
        .from('rs_fan_club_members')
        .delete()
        .eq('club_id', clubId)
        .eq('user_id', userId);
  }

  Future<List<RsFanClub>> getUserClubs(String userId) async {
    final memberRows = _asListOfMaps(
      await _client
          .from('rs_fan_club_members')
          .select('club_id')
          .eq('user_id', userId),
    );
    if (memberRows.isEmpty) return const [];

    final clubIds = memberRows
        .map((row) => row['club_id']?.toString() ?? '')
        .toList(growable: false);
    return _asListOfMaps(
      await _client.from('rs_fan_clubs').select().inFilter('id', clubIds),
    ).map(RsFanClub.fromJson).toList(growable: false);
  }

  Future<String?> getRayonPartnerId() => resolvePartnerId();

  Future<PartnerPaymentRoute> getActivePaymentRoute({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cachedRoute = _cachedPaymentRoute;
      if (cachedRoute != null && cachedRoute.isActive) {
        return cachedRoute;
      }
    }

    final partner = await resolvePartnerSummary();
    final partnerId = partner['id']?.toString().trim() ?? '';
    if (partnerId.isEmpty) {
      throw StateError('Rayon Sports partner record was not found.');
    }

    final routePayload = await _client.rpc(
      'get_partner_payment_route',
      params: <String, Object?>{
        'p_partner_id': partnerId,
        'p_country': AppMarket.countryCode,
      },
    );

    final routeData = _asMap(routePayload);
    final paymentRoute = PartnerPaymentRoute.fromJson(routeData);
    if (!paymentRoute.isActive) {
      throw StateError(
        'Rayon Sports payment routing is not active for ${paymentRoute.countryCode}.',
      );
    }
    if (paymentRoute.recipientCode.isEmpty) {
      throw StateError(
        'Rayon Sports payment routing is missing a recipient code.',
      );
    }

    _cachedPaymentRoute = paymentRoute;
    return paymentRoute;
  }

  Future<List<RsMembershipPackage>> getMembershipPackages({
    String? partnerId,
    bool includeInactive = false,
  }) async {
    final resolvedPartnerId = partnerId ?? await resolvePartnerId();
    if (resolvedPartnerId == null || resolvedPartnerId.isEmpty) {
      return [RsMembershipPackage.fallback()];
    }

    var query = _client
        .from('rs_membership_packages')
        .select()
        .eq('partner_id', resolvedPartnerId);

    if (!includeInactive) {
      query = query.eq('is_active', true);
    }

    final rows = _asListOfMaps(await query.order('sort_order').order('tier'));
    if (rows.isEmpty) {
      return [RsMembershipPackage.fallback()];
    }
    return rows.map(RsMembershipPackage.fromJson).toList(growable: false);
  }

  Future<bool> isGoogleWalletOperationallyReady() async {
    try {
      final response = await _client.functions.invoke(
        'wallet-issuer',
        body: const <String, Object?>{'action': 'health'},
      );
      final data = _asMap(response.data);
      return data['success'] == true && data['configured'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<RsFanMembership?> getRayonFanMembership(String userId) async {
    final partnerId = await resolvePartnerId();
    if (partnerId == null || partnerId.isEmpty) {
      return null;
    }
    return getFanMembership(userId, partnerId);
  }

  Future<RsFanMembership?> getFanMembership(
    String userId,
    String partnerId,
  ) async {
    final row = await _client
        .from('rs_fan_memberships')
        .select()
        .eq('partner_id', partnerId)
        .eq('user_id', userId)
        .maybeSingle();

    if (row == null) return null;
    return RsFanMembership.fromJson(_withResolvedDisplayName(_asMap(row)));
  }

  Future<List<RsAchievement>> getAchievements({
    required String userId,
    required String partnerId,
  }) async {
    return _asListOfMaps(
      await _client
          .from('rs_achievements')
          .select()
          .eq('partner_id', partnerId)
          .eq('user_id', userId)
          .order('earned_at', ascending: false),
    ).map(RsAchievement.fromJson).toList(growable: false);
  }

  Future<RsFanMembership> createFanMembership(
    String userId, {
    String? partnerId,
  }) async {
    final resolvedPartnerId = partnerId ?? await resolvePartnerId();
    if (resolvedPartnerId == null || resolvedPartnerId.isEmpty) {
      throw StateError('Rayon Sports partner record was not found.');
    }

    final membershipNumber =
        'RS-1968-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';

    final row = _asListOfMaps(
      await _client.from('rs_fan_memberships').insert(<String, Object?>{
        'user_id': userId,
        'partner_id': resolvedPartnerId,
        'display_name': _displayNameForUser(userId),
        'tier': 'fan',
        'points': 0,
        'membership_number': membershipNumber,
        'chapter': 'Kigali Central',
      }).select(),
    ).first;

    return RsFanMembership.fromJson(_withResolvedDisplayName(row));
  }

  Future<RsFanMembership> addPoints(
    String userId,
    String partnerId,
    int points,
    String reason,
  ) async {
    final current = await _client
        .from('rs_fan_memberships')
        .select()
        .eq('partner_id', partnerId)
        .eq('user_id', userId)
        .single();

    final currentPoints = (current['points'] as num?)?.toInt() ?? 0;
    final newPoints = currentPoints + points;
    final newTier = FanTierX.fromPoints(newPoints);

    final updated = _asListOfMaps(
      await _client
          .from('rs_fan_memberships')
          .update(<String, Object?>{
            'points': newPoints,
            'tier': newTier.name,
            'display_name': _displayNameForUser(userId),
          })
          .eq('partner_id', partnerId)
          .eq('user_id', userId)
          .select(),
    ).first;

    return RsFanMembership.fromJson(_withResolvedDisplayName(updated));
  }

  Future<List<RsRegistryMember>> getMembers(
    String partnerId, {
    String? searchQuery,
    FanTier? filterTier,
    String? region,
    int limit = 20,
    int offset = 0,
  }) async {
    if (partnerId.isEmpty) {
      return const <RsRegistryMember>[];
    }

    final rows = _asListOfMaps(
      await _client.rpc(
        'get_rayon_member_registry',
        params: <String, Object?>{
          'p_partner_id': partnerId,
          'p_search_query': _nullIfBlank(searchQuery),
          'p_filter_tier': filterTier?.name,
          'p_region': _nullIfBlank(region),
          'p_limit': limit,
          'p_offset': offset,
        },
      ),
    );

    return rows.map(RsRegistryMember.fromJson).toList(growable: false);
  }

  Future<List<RsFanClub>> getFanClubs(String partnerId, String? region) async {
    var query = _client
        .from('rs_fan_clubs')
        .select()
        .eq('partner_id', partnerId);

    if (region != null && region.isNotEmpty) {
      query = query.ilike('region', '%$region%');
    }

    return _asListOfMaps(
      await query.order('member_count', ascending: false),
    ).map(RsFanClub.fromJson).toList(growable: false);
  }

  RsJsonMap? _pickPreferredRayonPartner(List<RsJsonMap> rows) {
    for (final row in rows) {
      final slug = row['slug']?.toString();
      final id = row['id']?.toString().trim() ?? '';
      if (slug == 'rayon-sports' && id.isNotEmpty) {
        return row;
      }
    }

    for (final partnerName in rayon_identity.rayonSportsPartnerLookupNames) {
      for (final row in rows) {
        if (row['name']?.toString() == partnerName) {
          final id = row['id']?.toString().trim() ?? '';
          if (id.isNotEmpty) {
            return row;
          }
        }
      }
    }
    return null;
  }
}

List<RsJsonMap> _asListOfMaps(Object? value) {
  if (value is List) {
    return value
        .whereType<Map<String, dynamic>>()
        .map((row) => row.map((key, val) => MapEntry(key, val)))
        .toList(growable: false);
  }
  return const <Map<String, Object?>>[];
}

RsJsonMap _asMap(Object? value) {
  if (value is Map) {
    return value.map((key, val) => MapEntry('$key', val));
  }
  return const <String, Object?>{};
}

RsJsonMap? _asMapOrNull(Object? value) {
  if (value is Map) {
    return value.map((key, val) => MapEntry('$key', val));
  }
  return null;
}

String? _nullIfBlank(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
