import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../auth/providers/auth_provider.dart';
import '../../groups/providers/groups_provider.dart';
import '../providers/home_dashboard_provider.dart';
import '../widgets/home_quick_services.dart';
import '../widgets/home_sections.dart';
import '../widgets/home_shared.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Future<void> _refresh() async {
    ref.invalidate(homeDashboardProvider);
    ref.invalidate(myGroupsProvider);
    try {
      await Future.wait<void>([
        ref.read(homeDashboardProvider.future).then((_) {}),
        ref.read(myGroupsProvider.future).then((_) {}),
      ]);
    } catch (_) {
      // The inline sections render their own error states.
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final dashboardAsync = ref.watch(homeDashboardProvider);
    final groupsAsync = ref.watch(myGroupsProvider);
    final dashboard = dashboardAsync.valueOrNull;
    final groups = groupsAsync.valueOrNull ?? const [];
    final topPadding = MediaQuery.paddingOf(context).top;
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    final displayName = resolveDisplayName(
      context,
      user?.officialName,
      user?.fullName,
    );
    final colors = context.coolSemanticColors;

    return CoolScreenBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: RefreshIndicator(
          onRefresh: _refresh,
          displacement: 24,
          color: colors.accent,
          backgroundColor: colors.elevatedBackground,
          edgeOffset: topPadding + CoolSpace.x2,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  CoolSpace.x5,
                  topPadding + CoolSpace.x4,
                  CoolSpace.x5,
                  CoolSpace.x10 + bottomPadding + 108,
                ),
                sliver: SliverList.list(
                  children: [
                    HomeHeader(
                      displayName: displayName,
                      avatarUrl: user?.avatarUrl,
                      onNotificationsTap: () => context.push(AppRoutes.profile),
                    ),
                    const SizedBox(height: CoolSpace.x7),
                    HomeSavingsHeroCard(
                      totalSavingsRwf: dashboard?.totalBalance ?? 0,
                      monthlyNetChange: dashboard?.monthlyNetChange,
                      onOpenWallet: () =>
                          context.push(AppRoutes.settingsWallet),
                    ),
                    const SizedBox(height: CoolSpace.x6),
                    const HomeQuickServices(),
                    const SizedBox(height: CoolSpace.x8),
                    HomeCommunitiesSection(
                      groups: groups,
                      isLoading: groupsAsync.isLoading,
                      error: groupsAsync.hasError ? groupsAsync.error : null,
                      onViewAll: () =>
                          context.push(AppRoutes.contributionCircles),
                      onOpenGroup: (group) =>
                          openCommunityGroup(context, group),
                      onQuickContribution: (group) =>
                          openCommunityContribution(context, group),
                    ),
                    const SizedBox(height: CoolSpace.x8),
                    HomeOperationsSection(
                      transactions: dashboard?.recentTransactions ?? const [],
                      isLoading: dashboardAsync.isLoading,
                      error: dashboardAsync.hasError
                          ? dashboardAsync.error
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
