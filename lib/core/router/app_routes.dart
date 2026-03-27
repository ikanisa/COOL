import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

abstract final class AppRoutes {
  static const splash = '/';
  static const home = '/home';
  static const biopayTab = '/biopay-tab';
  static const groups = '/groups';
  static const groupCreate = '/groups/create';
  static const groupDetail = '/groups/:id';
  static const groupLedger = '/groups/:id/ledger';
  static const groupInvite = '/invite/:code';
  static const momo = '/momo';
  static const momoStatements = '/momo/statements';
  static const biopayHome = '/momo/biopay';
  static const biopayRegister = '/momo/biopay/register';
  static const biopayScan = '/momo/biopay/scan';
  static const biopayNfc = '/momo/biopay/nfc';
  static const partners = '/partners';
  static const rayonHome = '/partners/rayon-sports';
  static const rayonProfile = '/partners/rayon-sports/profile';
  static const rayonRegistry = '/partners/rayon-sports/registry';
  static const rayonClubs = '/partners/rayon-sports/clubs';
  static const rayonClubDetail = '/partners/rayon-sports/clubs/:clubId';
  static const rayonShop = '/partners/rayon-sports/shop';
  static const rayonShopCheckout = '/partners/rayon-sports/shop/checkout';
  static const rayonProductDetail =
      '/partners/rayon-sports/shop/product/:productId';
  static const rayonSupport = '/partners/rayon-sports/support';
  static const rayonSupportDetail =
      '/partners/rayon-sports/support/:initiativeId';
  static const rayonTickets = '/partners/rayon-sports/tickets';
  static const rayonMyTickets = '/partners/rayon-sports/tickets/my-tickets';
  static const rayonTicketConfirm =
      '/partners/rayon-sports/tickets/:ticketId/confirm';
  static const rayonMembership = '/partners/rayon-sports/membership';
  static const missions = '/missions';
  static const seasons = '/seasons';
  static const tokens = '/tokens';
  static const referral = '/referral';
  static const profile = '/profile';
  static const profileWallet = '/profile/wallet';
  static const profileAccount = '/profile/account';
  static const profileNotifications = '/profile/notifications';
  static const profilePrivacy = '/profile/privacy';
  static const profileOrders = '/profile/orders';
  static const profileHelp = '/profile/help';
  static const profileAbout = '/profile/about';

  static const scanner = '/scanner';

  static const admin = '/admin';
  static const adminPlatform = '/admin/platform';
  static const adminUsers = '/admin/users';
  static const adminPartners = '/admin/partners';
  static const adminServices = '/admin/services';
  static const adminQuickActions = '/admin/quick-actions';
  static const adminAppConfig = '/admin/app-config';
  static const adminSpecialProducts = '/admin/special-products';
  static const adminOperations = '/admin/operations';
  static const adminPartnerWorkspace = '/admin/partners/:partnerId';
  static const adminBankWorkspace = '/admin/banks/:partnerId';

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

  static String splashLocation({String? redirect}) {
    return _location(splash, redirect: redirect);
  }

  static String inviteLocation(String code) {
    return '/invite/${code.trim().toUpperCase()}';
  }

  static String rayonClubDetailLocation(String id) {
    return '/partners/rayon-sports/clubs/$id';
  }

  static String rayonSupportDetailLocation(String id) {
    return '/partners/rayon-sports/support/$id';
  }

  static String adminPartnerWorkspaceLocation(String partnerId) {
    return '/admin/partners/${partnerId.trim()}';
  }

  static String adminBankWorkspaceLocation(String partnerId) {
    return '/admin/banks/${partnerId.trim()}';
  }

  static String biopayScanLocation({required String mode}) {
    return _location(
      biopayScan,
      queryParameters: <String, String>{'mode': mode.trim()},
    );
  }

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

const _partnerDetailSlugs = {'urwego', 'equity', 'radiant', 'prisma'};
const appShellRootLocations = {
  AppRoutes.home,
  AppRoutes.groups,
  AppRoutes.biopayHome,
  AppRoutes.profile,
};

String? resolvePartnerDetailRedirect(String id) {
  if (id == 'rayon-sports') {
    return AppRoutes.rayonHome;
  }
  if (_partnerDetailSlugs.contains(id)) {
    return null;
  }
  return AppRoutes.partners;
}

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
