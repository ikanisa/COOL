import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

abstract final class AppRoutes {
  static const splash = '/';
  static const home = '/home';

  // ── Contribution groups ─────────────────────────────────────────
  static const groups = '/groups';
  static const groupCreate = '/groups/create';
  static const groupDetail = '/groups/:id';
  static const groupLedger = '/groups/:id/ledger';
  static const groupInvite = '/invite/:code';

  // ── MoMo ────────────────────────────────────────────────────────
  static const momo = '/momo';
  static const momoStatements = '/momo/statements';

  // ── BioPay ──────────────────────────────────────────────────────
  static const biopayHome = '/momo/biopay';
  static const biopayRegister = '/momo/biopay/register';
  static const biopayScan = '/momo/biopay/scan';
  static const biopayNfc = '/momo/biopay/nfc';

  // ── Rayon Sports FC — Flattened routes ──────────────────────────
  // (Previously under /rayon-sports/* — now root-level)

  /// Fan profile + identity.
  static const fanProfile = '/fan-profile';

  /// Member registry (public fan directory).
  static const registry = '/registry';

  /// Fan clubs.
  static const fanClubs = '/fan-clubs';
  static const fanClubDetail = '/fan-clubs/:clubId';

  /// Club shop.
  static const shop = '/shop';
  static const shopCheckout = '/shop/checkout';
  static const shopProductDetail = '/shop/product/:productId';

  /// Contributions (club initiatives / support).
  static const contributions = '/contributions';
  static const contributionDetail = '/contributions/:initiativeId';

  /// Contribution circles (group fundraising + chat).
  static const contributionCircles = '/contribution-circles';
  static const contributionCircleDetail = '/contribution-circles/:groupId';

  /// Ticketing.
  static const tickets = '/tickets';
  static const myTickets = '/tickets/my-tickets';
  static const ticketConfirm = '/tickets/:ticketId/confirm';

  /// Membership tiers & perks.
  static const membership = '/membership';

  // ── Legacy aliases (keep old references compiling) ─────────────
  static const rayonHome = fanProfile;
  static const rayonProfile = fanProfile;
  static const rayonRegistry = registry;
  static const rayonClubs = fanClubs;
  static const rayonClubDetail = fanClubDetail;
  static const rayonShop = shop;
  static const rayonShopCheckout = shopCheckout;
  static const rayonProductDetail = shopProductDetail;
  static const rayonSupport = contributions;
  static const rayonSupportDetail = contributionDetail;
  static const rayonTickets = tickets;
  static const rayonMyTickets = myTickets;
  static const rayonTicketConfirm = ticketConfirm;
  static const rayonMembership = membership;
  static const rayonContributionCircles = contributionCircles;
  static const rayonContributionCircleDetail = contributionCircleDetail;

  /// Legacy alias — partner network is now contributions.
  static const partners = contributions;

  // ── Rewards Compatibility ───────────────────────────────────────
  static const missions = '/missions';
  static const seasons = '/seasons';
  static const tokens = '/tokens';
  static const referral = '/referral';
  static const gamification = '/gamification';
  static const rewards = tokens;
  static const rewardsActivities = missions;

  // ── Fan Engagement ──────────────────────────────────────────────
  static const matchEngagement = '/match/:matchId/engage';
  static const fanLeaderboard = '/leaderboard';
  static const leaderboard = fanLeaderboard;

  // ── Profile ─────────────────────────────────────────────────────
  static const profile = '/profile';
  static const profileWallet = '/profile/wallet';
  static const profileAccount = '/profile/account';
  static const profileNotifications = '/profile/notifications';
  static const profilePrivacy = '/profile/privacy';
  static const profileOrders = '/profile/orders';
  static const profileHelp = '/profile/help';
  static const profileAbout = '/profile/about';
  static const settings = profile;
  static const settingsWallet = profileWallet;
  static const settingsAccount = profileAccount;
  static const settingsNotifications = profileNotifications;
  static const settingsPrivacy = profilePrivacy;
  static const settingsOrders = profileOrders;
  static const settingsHelp = profileHelp;
  static const settingsAbout = profileAbout;

  // ── Utilities ───────────────────────────────────────────────────
  static const scanner = '/scanner';

  // ── Admin ───────────────────────────────────────────────────────
  static const admin = '/admin';
  static const adminPlatform = '/admin/platform';
  static const adminPartners = '/admin/partners';
  static const adminUsers = '/admin/users';
  static const adminServices = '/admin/services';
  static const adminQuickActions = '/admin/quick-actions';
  static const adminAppConfig = '/admin/app-config';
  static const adminSpecialProducts = '/admin/special-products';
  static const adminOperations = '/admin/operations';

  static const adminMissions = '/admin/missions';
  static const adminSeasons = '/admin/seasons';
  static const adminRoles = '/admin/roles';
  static const adminAnalytics = '/admin/analytics';
  static const adminAuditLog = '/admin/audit-log';
  static const adminAiContent = '/admin/ai-content';

  static const adminRayon = '/admin/rayon';
  static const adminRayonMatches = '/admin/rayon/matches';
  static const adminRayonTickets = '/admin/rayon/tickets';
  static const adminRayonShop = '/admin/rayon/shop';
  static const adminRayonOrders = '/admin/rayon/orders';
  static const adminRayonMembers = '/admin/rayon/members';
  static const adminRayonPackages = '/admin/rayon/packages';
  static const adminRayonFinance = '/admin/rayon/finance';
  static const adminRayonInitiatives = '/admin/rayon/initiatives';
  static const adminRayonEngagement = '/admin/rayon/engagement';

  // ── Location builders ─────────────────────────────────────────

  static String splashLocation({String? redirect}) {
    return _location(splash, redirect: redirect);
  }

  static String profileWalletLocation({String? redirect}) {
    return _location(profileWallet, redirect: redirect);
  }

  static String settingsWalletLocation({String? redirect}) {
    return profileWalletLocation(redirect: redirect);
  }

  static String inviteLocation(String code) {
    return '/invite/${code.trim().toUpperCase()}';
  }

  static String fanClubDetailLocation(String id) {
    return '/fan-clubs/$id';
  }

  static String contributionDetailLocation(String id) {
    return '/contributions/$id';
  }

  static String contributionCircleDetailLocation(String groupId) {
    return '/contribution-circles/$groupId';
  }

  static String adminPartnerWorkspaceLocation(String partnerId) {
    return '$adminPartners/${partnerId.trim()}';
  }

  static String adminBankWorkspaceLocation(String bankId) {
    return '/admin/banks/${bankId.trim()}';
  }

  static String shopProductDetailLocation(String id) {
    return '/shop/product/$id';
  }

  static String ticketConfirmLocation(String ticketId) {
    return '/tickets/$ticketId/confirm';
  }

  static String biopayScanLocation({required String mode}) {
    return _location(
      biopayScan,
      queryParameters: <String, String>{'mode': mode.trim()},
    );
  }

  static String matchEngagementLocation(String matchId) =>
      '/match/$matchId/engage';

  // ── Legacy location aliases (keep references compiling) ────────
  static String rayonClubDetailLocation(String id) => fanClubDetailLocation(id);

  static String rayonSupportDetailLocation(String id) =>
      contributionDetailLocation(id);

  static String _location(
    String path, {
    Map<String, String>? queryParameters,
    String? redirect,
  }) {
    final parameters = <String, String>{
      ...?queryParameters,
      if (redirect != null && redirect.trim().isNotEmpty)
        'redirect': redirect.trim(),
    };
    if (parameters.isEmpty) {
      return path;
    }
    return Uri(path: path, queryParameters: parameters).toString();
  }
}

const appShellRootLocations = {
  AppRoutes.home,
  AppRoutes.groups,
  AppRoutes.contributionCircles,
  AppRoutes.biopayHome,
  AppRoutes.profile,
};

bool isShellRootLocation(String location) {
  final trimmed = location.trim();
  if (trimmed.isEmpty) {
    return false;
  }

  final uri = Uri.tryParse(trimmed);
  final path = uri?.path.isNotEmpty == true ? uri!.path : trimmed;
  return appShellRootLocations.contains(path);
}

void openQuickActionRoute(BuildContext context, String location) {
  final trimmed = location.trim();
  if (trimmed.isEmpty) {
    return;
  }

  if (isShellRootLocation(trimmed)) {
    context.go(trimmed);
    return;
  }

  context.push(trimmed);
}

String? resolvePartnerDetailRedirect(String partnerSlug) {
  final normalized = partnerSlug.trim().toLowerCase();
  if (normalized.isEmpty) {
    return AppRoutes.partners;
  }

  switch (normalized) {
    case 'rayon-sports':
    case 'rayon_sports':
    case 'rayon sports':
      return AppRoutes.rayonHome;
    case 'radiant':
      return null;
    default:
      return AppRoutes.partners;
  }
}
