import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../auth/providers/auth_provider.dart';
import '../../groups/models/group.dart';
import '../../groups/providers/groups_provider.dart';
import '../models/home_dashboard_data.dart';
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
    ref.invalidate(publicGroupsProvider);
    try {
      await Future.wait<void>([
        ref.read(homeDashboardProvider.future).then((_) {}),
        ref.read(myGroupsProvider.future).then((_) {}),
        ref.read(publicGroupsProvider.future).then((_) {}),
      ]);
    } catch (_) {
      // The inline sections render their own error states.
    }
  }

  String? _primarySavingsGroupId(List<Group> groups) {
    for (final group in groups) {
      final groupId = group.id?.trim() ?? '';
      if (group.type == 'saving' && groupId.isNotEmpty) {
        return groupId;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final dashboardAsync = ref.watch(homeDashboardProvider);
    final myGroupsAsync = ref.watch(myGroupsProvider);
    final publicGroupsAsync = ref.watch(publicGroupsProvider);
    final dashboard = dashboardAsync.valueOrNull;
    final List<HomeDashboardTransaction> recentTransactions =
        dashboard?.recentTransactions ?? const <HomeDashboardTransaction>[];
    final myGroups = myGroupsAsync.valueOrNull ?? const <Group>[];
    final publicGroups = publicGroupsAsync.valueOrNull ?? const <Group>[];
    final primarySavingsGroupId = _primarySavingsGroupId(myGroups);
    final topPadding = MediaQuery.paddingOf(context).top;
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    final displayName = resolveDisplayName(
      context,
      user?.officialName,
      user?.fullName,
    );
    final colors = context.coolSemanticColors;
    final homeSections = <Widget>[
      HomeHeader(
        displayName: displayName,
        avatarUrl: user?.avatarUrl,
        onNotificationsTap: () => context.push(AppRoutes.profile),
      ),
      const SizedBox(height: CoolSpace.x6),
      HomeSavingsHeroCard(
        totalSavingsRwf: dashboard?.totalBalance ?? 0,
        monthlyNetChange: dashboard?.monthlyNetChange,
        isNewUser:
            myGroups.isEmpty &&
            publicGroups.isEmpty &&
            (dashboard?.totalBalance ?? 0) == 0,
        onOpenSavings: () {
          if (primarySavingsGroupId == null) {
            context.push(AppRoutes.groups);
            return;
          }
          context.push(AppRoutes.groupDetailLocation(primarySavingsGroupId));
        },
      ),
      const SizedBox(height: CoolSpace.x6),
      const HomeQuickServices(),
    ];

    if (publicGroups.isNotEmpty) {
      homeSections.addAll([
        const SizedBox(height: CoolSpace.x6),
        HomeCommunitiesSection(
          groups: publicGroups,
          isLoading: publicGroupsAsync.isLoading,
          error: publicGroupsAsync.hasError ? publicGroupsAsync.error : null,
          onViewAll: () => context.push(AppRoutes.groups),
          onOpenGroup: (group) => openCommunityGroup(context, group),
          onQuickContribution: (group) => openCommunityContribution(
            context,
            group,
            memberGroupIds: myGroups
                .map((item) => item.id ?? '')
                .where((id) => id.isNotEmpty)
                .toSet(),
          ),
        ),
      ]);
    }

    if (recentTransactions.isNotEmpty) {
      homeSections.addAll([
        const SizedBox(height: CoolSpace.x6),
        HomeOperationsSection(
          transactions: recentTransactions,
          isLoading: dashboardAsync.isLoading,
          error: dashboardAsync.hasError ? dashboardAsync.error : null,
        ),
      ]);
    }

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
                sliver: SliverList.list(children: homeSections),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
