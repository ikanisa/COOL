import 'package:go_router/go_router.dart';

import '../../features/rayon/screens/club_shop_screen.dart';
import '../../features/rayon/screens/contribution_circle_detail_screen.dart';
import '../../features/rayon/screens/contribution_circles_screen.dart';
import '../../features/rayon/screens/fan_club_detail_screen.dart';
import '../../features/rayon/screens/fan_clubs_screen.dart';
import '../../features/rayon/screens/fan_profile_screen.dart';
import '../../features/rayon/screens/member_registry_screen.dart';
import '../../features/rayon/screens/membership_tiers_screen.dart';
import '../../features/rayon/screens/my_tickets_screen.dart';
import '../../features/rayon/screens/product_detail_screen.dart';
import '../../features/rayon/screens/shop_checkout_screen.dart';
import '../../features/rayon/screens/support_detail_screen.dart';
import '../../features/rayon/screens/support_screen.dart';
import '../../features/rayon/screens/ticket_confirmation_screen.dart';
import '../../features/rayon/screens/tickets_screen.dart';
import '../../features/rayon/screens/match_engagement_screen.dart';
import '../../features/rayon/screens/fan_leaderboard_screen.dart';
import 'app_router.dart';

String _redirectWithQuery(GoRouterState state, String target) {
  final queryParameters = state.uri.queryParameters;
  if (queryParameters.isEmpty) {
    return target;
  }
  return Uri(path: target, queryParameters: queryParameters).toString();
}

String _redirectLegacyInvite(GoRouterState state) {
  final inviteCode = state.pathParameters['code']?.trim().toUpperCase();
  final queryParameters = <String, String>{
    ...state.uri.queryParameters,
    if (inviteCode != null && inviteCode.isNotEmpty) 'invite_code': inviteCode,
  };
  return Uri(
    path: AppRoutes.contributionCircles,
    queryParameters: queryParameters.isEmpty ? null : queryParameters,
  ).toString();
}

/// Rayon Sports FC feature routes — ROUGEBLACK system.
///
/// Previously nested under `/rayon-sports/*`, now flattened to root-level
/// paths for cleaner navigation and simpler deep-linking.
RouteBase partnerRoutes({
  required ({bool isAdmin, bool hasSession}) Function() readAuthSnapshot,
  required dynamic Function() readFeatureFlags,
}) {
  return ShellRoute(
    builder: (context, state, child) => child,
    routes: [
      // ── Legacy groups + invite routes ───────────────────────────
      GoRoute(
        path: AppRoutes.groupInvite,
        redirect: (context, state) => _redirectLegacyInvite(state),
      ),
      GoRoute(
        path: AppRoutes.groupCreate,
        redirect: (context, state) =>
            _redirectWithQuery(state, AppRoutes.contributionCircles),
      ),
      GoRoute(
        path: AppRoutes.groupLedger,
        redirect: (context, state) => _redirectWithQuery(
          state,
          AppRoutes.contributionCircleDetailLocation(
            state.pathParameters['id'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.groupDetail,
        redirect: (context, state) => _redirectWithQuery(
          state,
          AppRoutes.contributionCircleDetailLocation(
            state.pathParameters['id'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.groups,
        redirect: (context, state) =>
            _redirectWithQuery(state, AppRoutes.contributionCircles),
      ),

      // ── Legacy partner / Rayon routes ───────────────────────────
      GoRoute(
        path: '/partners',
        redirect: (context, state) =>
            _redirectWithQuery(state, AppRoutes.partners),
      ),
      GoRoute(
        path: '/partners/rayon-sports',
        redirect: (context, state) =>
            _redirectWithQuery(state, AppRoutes.rayonHome),
      ),
      GoRoute(
        path: '/partners/rayon-sports/profile',
        redirect: (context, state) =>
            _redirectWithQuery(state, AppRoutes.fanProfile),
      ),
      GoRoute(
        path: '/partners/rayon-sports/registry',
        redirect: (context, state) =>
            _redirectWithQuery(state, AppRoutes.registry),
      ),
      GoRoute(
        path: '/partners/rayon-sports/clubs',
        redirect: (context, state) =>
            _redirectWithQuery(state, AppRoutes.fanClubs),
      ),
      GoRoute(
        path: '/partners/rayon-sports/clubs/:clubId',
        redirect: (context, state) => _redirectWithQuery(
          state,
          AppRoutes.fanClubDetailLocation(state.pathParameters['clubId'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/partners/rayon-sports/membership',
        redirect: (context, state) =>
            _redirectWithQuery(state, AppRoutes.membership),
      ),
      GoRoute(
        path: '/partners/rayon-sports/shop',
        redirect: (context, state) => _redirectWithQuery(state, AppRoutes.shop),
      ),
      GoRoute(
        path: '/partners/rayon-sports/shop/checkout',
        redirect: (context, state) =>
            _redirectWithQuery(state, AppRoutes.shopCheckout),
      ),
      GoRoute(
        path: '/partners/rayon-sports/shop/product/:productId',
        redirect: (context, state) => _redirectWithQuery(
          state,
          AppRoutes.shopProductDetailLocation(
            state.pathParameters['productId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/partners/rayon-sports/support',
        redirect: (context, state) =>
            _redirectWithQuery(state, AppRoutes.contributions),
      ),
      GoRoute(
        path: '/partners/rayon-sports/support/:initiativeId',
        redirect: (context, state) => _redirectWithQuery(
          state,
          AppRoutes.contributionDetailLocation(
            state.pathParameters['initiativeId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/partners/rayon-sports/tickets/my-tickets',
        redirect: (context, state) =>
            _redirectWithQuery(state, AppRoutes.myTickets),
      ),
      GoRoute(
        path: '/partners/rayon-sports/tickets/:ticketId/confirm',
        redirect: (context, state) => _redirectWithQuery(
          state,
          AppRoutes.ticketConfirmLocation(
            state.pathParameters['ticketId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/partners/rayon-sports/tickets',
        redirect: (context, state) =>
            _redirectWithQuery(state, AppRoutes.tickets),
      ),
      GoRoute(
        path: '/rayon/registry',
        redirect: (context, state) =>
            _redirectWithQuery(state, AppRoutes.registry),
      ),

      // ── Fan profile ──────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.fanProfile,
        pageBuilder: (context, state) => coolPageTransition(
          context: context,
          state: state,
          child: const FanProfileScreen(),
        ),
      ),

      // ── Member registry ──────────────────────────────────────────
      GoRoute(
        path: AppRoutes.registry,
        pageBuilder: (context, state) => coolPageTransition(
          context: context,
          state: state,
          child: const MemberRegistryScreen(),
        ),
      ),

      // ── Fan clubs ────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.fanClubs,
        pageBuilder: (context, state) => coolPageTransition(
          context: context,
          state: state,
          child: const FanClubsScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.fanClubDetail,
        pageBuilder: (context, state) {
          final clubId = state.pathParameters['clubId'] ?? '';
          return coolPageTransition(
            context: context,
            state: state,
            child: FanClubDetailScreen(clubId: clubId),
          );
        },
      ),

      // ── Club shop ────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.shop,
        pageBuilder: (context, state) => coolPageTransition(
          context: context,
          state: state,
          child: const ClubShopScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.shopCheckout,
        pageBuilder: (context, state) => coolPageTransition(
          context: context,
          state: state,
          child: const ShopCheckoutScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.shopProductDetail,
        pageBuilder: (context, state) {
          final productId = state.pathParameters['productId'] ?? '';
          return coolPageTransition(
            context: context,
            state: state,
            child: ProductDetailScreen(productId: productId),
          );
        },
      ),

      // ── Contributions (initiatives / support) ────────────────────
      GoRoute(
        path: AppRoutes.contributions,
        pageBuilder: (context, state) => coolPageTransition(
          context: context,
          state: state,
          child: const SupportScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.contributionDetail,
        pageBuilder: (context, state) {
          final initiativeId = state.pathParameters['initiativeId'] ?? '';
          return coolPageTransition(
            context: context,
            state: state,
            child: SupportDetailScreen(initiativeId: initiativeId),
          );
        },
      ),

      // ── Contribution Circles (group fundraising + chat) ────────────
      GoRoute(
        path: AppRoutes.contributionCircles,
        pageBuilder: (context, state) => coolPageTransition(
          context: context,
          state: state,
          child: const ContributionCirclesScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.contributionCircleDetail,
        pageBuilder: (context, state) {
          final groupId = state.pathParameters['groupId'] ?? '';
          return coolPageTransition(
            context: context,
            state: state,
            child: ContributionCircleDetailScreen(groupId: groupId),
          );
        },
      ),

      // ── Ticketing ────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.tickets,
        pageBuilder: (context, state) => coolPageTransition(
          context: context,
          state: state,
          child: const TicketsScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.myTickets,
        pageBuilder: (context, state) => coolPageTransition(
          context: context,
          state: state,
          child: const MyTicketsScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.ticketConfirm,
        pageBuilder: (context, state) {
          final ticketId = state.pathParameters['ticketId'] ?? '';
          return coolPageTransition(
            context: context,
            state: state,
            child: TicketConfirmationScreen(ticketId: ticketId),
          );
        },
      ),

      // ── Membership ──────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.membership,
        pageBuilder: (context, state) => coolPageTransition(
          context: context,
          state: state,
          child: const MembershipTiersScreen(),
        ),
      ),

      // ── Match Engagement ────────────────────────────────────────
      GoRoute(
        path: AppRoutes.matchEngagement,
        pageBuilder: (context, state) {
          final matchId = state.pathParameters['matchId'] ?? '';
          return coolPageTransition(
            context: context,
            state: state,
            child: MatchEngagementScreen(matchId: matchId),
          );
        },
      ),

      // ── Fan Leaderboard ────────────────────────────────────────
      GoRoute(
        path: AppRoutes.fanLeaderboard,
        pageBuilder: (context, state) => coolPageTransition(
          context: context,
          state: state,
          child: const FanLeaderboardScreen(),
        ),
      ),
    ],
  );
}
