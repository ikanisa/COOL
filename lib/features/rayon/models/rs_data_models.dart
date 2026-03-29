part of 'rs_models.dart';

class RayonSportsData {
  const RayonSportsData({
    required this.partnerId,
    required this.membership,
    required this.joinedClubIds,
    required this.registryMembers,
    required this.achievements,
    required this.clubs,
    required this.products,
    required this.initiatives,
    required this.matches,
    required this.tickets,
    this.banners = const [],
  });

  final String partnerId;
  final FanMembership? membership;
  final Set<String> joinedClubIds;
  final List<RsRegistryMember> registryMembers;
  final List<RsAchievement> achievements;
  final List<RsFanClub> clubs;
  final List<RsProduct> products;
  final List<RsInitiative> initiatives;
  final List<RsMatch> matches;
  final List<RsTicket> tickets;
  final List<RsHomeBanner> banners;

  RsFanClub? clubById(String id) {
    for (final club in clubs) {
      if (club.id == id) return club;
    }
    return null;
  }

  RsInitiative? initiativeById(String id) {
    for (final initiative in initiatives) {
      if (initiative.id == id) return initiative;
    }
    return null;
  }

  List<RsProduct> productsByIds(Iterable<String> ids) {
    final idSet = ids.toSet();
    return products.where((p) => idSet.contains(p.id)).toList();
  }
}
