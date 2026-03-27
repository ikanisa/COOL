import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../rayon/models/rs_models.dart';

class RayonSportsDashboardRepository {
  RayonSportsDashboardRepository({
    required SupabaseClient client,
    required Future<String?> Function() resolvePartnerId,
    required RsJsonMap Function(RsJsonMap row) withResolvedDisplayName,
  }) : _client = client,
       _resolvePartnerId = resolvePartnerId,
       _withResolvedDisplayName = withResolvedDisplayName;

  final SupabaseClient _client;
  final Future<String?> Function() _resolvePartnerId;
  final RsJsonMap Function(RsJsonMap row) _withResolvedDisplayName;

  Future<RayonSportsData> loadData({String? userId}) async {
    try {
      final partnerId = await _resolvePartnerId();
      if (partnerId == null) {
        debugPrint('[RayonRepo] ⚠️ Partner not found in database');
        throw StateError(
          'Rayon Sports partner not found. '
          'Ensure seed data has been applied.',
        );
      }

      final membershipRowsFuture = _client
          .from('rs_fan_memberships')
          .select()
          .eq('partner_id', partnerId)
          .order('points', ascending: false);
      final joinedClubRowsFuture = userId == null
          ? Future.value(const <Map<String, Object?>>[])
          : _client
                .from('rs_fan_club_members')
                .select('club_id')
                .eq('user_id', userId)
                .then(_asListOfMaps);
      final achievementsRowsFuture = userId == null
          ? Future.value(const <Map<String, Object?>>[])
          : _client
                .from('rs_achievements')
                .select()
                .eq('partner_id', partnerId)
                .eq('user_id', userId)
                .order('earned_at', ascending: false)
                .then(_asListOfMaps);
      final clubsRowsFuture = _client
          .from('rs_fan_clubs')
          .select()
          .eq('partner_id', partnerId)
          .order('member_count', ascending: false);
      final productsRowsFuture = _client
          .from('rs_shop_products')
          .select()
          .eq('partner_id', partnerId)
          .eq('is_active', true)
          .order('price');
      final initiativesRowsFuture = _client
          .from('rs_initiatives')
          .select()
          .eq('partner_id', partnerId)
          .eq('is_active', true)
          .order('ends_at');
      final matchesRowsFuture = _client
          .from('rs_matches')
          .select()
          .eq('partner_id', partnerId)
          .order('match_date');
      final bannersRowsFuture = _client
          .from('rs_home_banners')
          .select()
          .eq('is_active', true)
          .order('sort_order');

      final rawMembershipRows = await membershipRowsFuture;
      final membershipRows = _asListOfMaps(rawMembershipRows);
      final joinedClubRows = await joinedClubRowsFuture;
      final achievementsRows = await achievementsRowsFuture;
      final rawClubsRows = await clubsRowsFuture;
      final rawProductsRows = await productsRowsFuture;
      final rawInitiativesRows = await initiativesRowsFuture;
      final rawMatchesRows = await matchesRowsFuture;
      final rawBannersRows = await bannersRowsFuture;

      final joinedClubIds = joinedClubRows
          .map((row) => row['club_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      final registry = membershipRows
          .map(
            (row) => RsRegistryMember.fromJson(_withResolvedDisplayName(row)),
          )
          .toList(growable: false);

      RsJsonMap? currentMembership;
      if (userId != null) {
        for (final row in membershipRows) {
          if (row['user_id']?.toString() == userId) {
            currentMembership = row;
            break;
          }
        }
      }

      final achievements = achievementsRows
          .map(RsAchievement.fromJson)
          .toList(growable: false);
      final clubs = _asListOfMaps(
        rawClubsRows,
      ).map(RsFanClub.fromJson).toList(growable: false);
      final products = _asListOfMaps(
        rawProductsRows,
      ).map(RsShopProduct.fromJson).toList(growable: false);
      final initiatives = _asListOfMaps(
        rawInitiativesRows,
      ).map(RsInitiative.fromJson).toList(growable: false);
      final matches = _asListOfMaps(
        rawMatchesRows,
      ).map(RsMatch.fromJson).toList(growable: false);
      final banners = _asListOfMaps(
        rawBannersRows,
      ).map(RsHomeBanner.fromJson).toList(growable: false);

      final matchesById = <String, RsMatch>{
        for (final match in matches) match.id: match,
      };

      final ticketRows = userId == null
          ? const <Map<String, Object?>>[]
          : _asListOfMaps(
              await _client
                  .from('rs_tickets')
                  .select()
                  .eq('user_id', userId)
                  .order('purchased_at', ascending: false),
            );
      final tickets = ticketRows
          .map((row) {
            final match = matchesById[row['match_id']?.toString()];
            return RsTicket.fromJson(<String, Object?>{
              ...row,
              'match': match?.toJson(),
              'fan_id': currentMembership?['membership_number'],
            });
          })
          .toList(growable: false);

      if (membershipRows.isEmpty &&
          clubs.isEmpty &&
          products.isEmpty &&
          initiatives.isEmpty &&
          matches.isEmpty &&
          tickets.isEmpty) {
        debugPrint(
          '[RayonRepo] ⚠️ All Rayon tables are empty for '
          'partner $partnerId — returning empty state',
        );
      }

      final membership = currentMembership == null
          ? null
          : RsFanMembership.fromJson(
              _withResolvedDisplayName(currentMembership),
            );

      return RayonSportsData(
        partnerId: partnerId,
        membership: membership,
        joinedClubIds: joinedClubIds,
        registryMembers: registry,
        achievements: achievements,
        clubs: clubs,
        products: products,
        initiatives: initiatives,
        matches: matches,
        tickets: tickets,
        banners: banners,
      );
    } catch (error, stack) {
      debugPrint('[RayonRepo] ❌ loadData failed: $error');
      debugPrint('[RayonRepo] $stack');
      rethrow;
    }
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
