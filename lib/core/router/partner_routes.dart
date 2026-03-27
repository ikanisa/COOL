import 'package:go_router/go_router.dart';

import '../../core/models/engagement_feature_flags.dart';

import '../../features/partners/rayon/screens/club_shop_screen.dart';
import '../../features/partners/rayon/screens/fan_club_detail_screen.dart';
import '../../features/partners/rayon/screens/fan_clubs_screen.dart';
import '../../features/partners/rayon/screens/fan_profile_screen.dart';
import '../../features/partners/rayon/screens/member_registry_screen.dart';
import '../../features/partners/rayon/screens/membership_tiers_screen.dart';
import '../../features/partners/rayon/screens/my_tickets_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/partners/rayon/screens/product_detail_screen.dart';
import '../../features/partners/rayon/screens/shop_checkout_screen.dart';
import '../../features/partners/rayon/screens/support_detail_screen.dart';
import '../../features/partners/rayon/screens/support_screen.dart';
import '../../features/partners/rayon/screens/ticket_confirmation_screen.dart';
import '../../features/partners/rayon/screens/tickets_screen.dart';
import '../../features/partners/screens/bank_partner_screen.dart';
import '../../features/partners/screens/partners_screen.dart';
import '../../features/partners/screens/prisma_partner_screen.dart';
import '../../features/partners/screens/radiant_partner_screen.dart';
import '../../shared/widgets/kill_switch_gate.dart';
import '../../shared/widgets/secure_screen_wrapper.dart';
import 'app_redirects.dart';
import 'app_routes.dart';

/// Typedef for an auth snapshot read function used by routes that need feature
/// flag + auth checks.
typedef AuthSnapshotReader = ({bool isAdmin, bool hasSession}) Function();

/// Typedef for feature flags read function.
typedef FeatureFlagsReader = EngagementFeatureFlags Function();

/// Partner + Rayon Sports route tree nested under [AppRoutes.partners].
GoRoute partnerRoutes({
  required AuthSnapshotReader readAuthSnapshot,
  required FeatureFlagsReader readFeatureFlags,
}) {
  return GoRoute(
    path: AppRoutes.partners,
    builder: (context, state) => const PartnersScreen(),
    routes: [
      GoRoute(
        path: 'rayon-sports',
        builder: (context, state) => const HomeScreen(),
        routes: [
          GoRoute(
            path: 'profile',
            builder: (context, state) => const FanProfileScreen(),
          ),
          GoRoute(
            path: 'membership',
            builder: (context, state) => const MembershipTiersScreen(),
          ),
          GoRoute(
            path: 'registry',
            builder: (context, state) => const MemberRegistryScreen(),
          ),
          GoRoute(
            path: 'clubs',
            builder: (context, state) => const FanClubsScreen(),
            routes: [
              GoRoute(
                path: ':clubId',
                builder: (context, state) => FanClubDetailScreen(
                  clubId: state.pathParameters['clubId'] ?? '',
                  referralParameters: state.uri.queryParameters,
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'shop',
            builder: (context, state) => const ClubShopScreen(),
            routes: [
              GoRoute(
                path: 'checkout',
                builder: (context, state) => SecureScreenWrapper(
                  child: ShopCheckoutScreen(
                    referralParameters: state.uri.queryParameters,
                  ),
                ),
              ),
              GoRoute(
                path: 'product/:productId',
                builder: (context, state) => ProductDetailScreen(
                  productId: state.pathParameters['productId'] ?? '',
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'support',
            builder: (context, state) => const SupportScreen(),
            routes: [
              GoRoute(
                path: ':initiativeId',
                builder: (context, state) => SupportDetailScreen(
                  initiativeId: state.pathParameters['initiativeId'] ?? '',
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'tickets',
            builder: (context, state) {
              final authSnapshot = readAuthSnapshot();
              final featureFlags = readFeatureFlags();
              return KillSwitchGate(
                enabled: featureFlags.isTicketPurchaseEnabled(
                  isAdmin: authSnapshot.isAdmin,
                ),
                featureName: 'Ticket Purchase',
                child: TicketsScreen(
                  referralParameters: state.uri.queryParameters,
                ),
              );
            },
            routes: [
              GoRoute(
                path: 'my-tickets',
                builder: (context, state) => const MyTicketsScreen(),
              ),
              GoRoute(
                path: ':ticketId/confirm',
                builder: (context, state) => TicketConfirmationScreen(
                  ticketId: state.pathParameters['ticketId'] ?? '',
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: ':id',
        redirect: (context, state) =>
            resolvePartnerDetailRedirect(state.pathParameters['id']!),
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return switch (id) {
            'urwego' => BankPartnerScreen(bankId: id),
            'equity' => BankPartnerScreen(bankId: id),
            'radiant' => const RadiantPartnerScreen(),
            'prisma' => const PrismaPartnerScreen(),
            _ => BankPartnerScreen(bankId: id),
          };
        },
      ),
    ],
  );
}
