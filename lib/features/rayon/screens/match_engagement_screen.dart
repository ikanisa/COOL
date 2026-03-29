import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/rs_colors.dart';
import '../../../core/theme/rs_text_styles.dart';
import '../../../shared/widgets/cool_card.dart';
import '../models/rs_models.dart';
import '../providers/rayon_sports_provider.dart';
import '../providers/rs_engagement_provider.dart';
import '../repositories/rayon_sports_repository.dart';
import '../widgets/partner_navigation.dart';
import '../widgets/rayon_state_views.dart';

part '../widgets/match_engagement_parts.dart';

/// Match Engagement Hub — three-tab screen per match:
/// 1. POLLS — vote on pre-match polls
/// 2. PREDICT — score prediction + MOTM
/// 3. RECAP — AI commentary (post-match)
class MatchEngagementScreen extends ConsumerStatefulWidget {
  const MatchEngagementScreen({super.key, required this.matchId});

  final String matchId;

  @override
  ConsumerState<MatchEngagementScreen> createState() =>
      _MatchEngagementScreenState();
}

class _MatchEngagementScreenState extends ConsumerState<MatchEngagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    // Find the match from loaded data.
    final rayonState = ref.watch(rayonSportsProvider);
    final match = rayonState.data.valueOrNull?.matches
        .where((m) => m.id == widget.matchId)
        .firstOrNull;

    return Scaffold(
      backgroundColor: colors.appBackground,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            pinned: true,
            floating: true,
            expandedHeight: 0,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: buildPartnerBackButton(
              context,
              fallbackLocation: AppRoutes.tickets,
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'MATCH ',
                      style: RsTextStyles.sectionTitle(color: RsColors.rsWhite),
                    ),
                    Text(
                      'HUB',
                      style: RsTextStyles.sectionTitle(color: RsColors.rsRed),
                    ),
                  ],
                ),
                if (match != null)
                  Text(
                    '${match.homeTeam} vs ${match.awayTeam}',
                    style: text.rayon(
                      theme.textTheme.bodySmall,
                      fontWeight: FontWeight.w600,
                      color: colors.tertiaryText,
                    ),
                  ),
              ],
            ),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: RsColors.rsRed,
              indicatorWeight: 3,
              labelColor: RsColors.rsWhite,
              unselectedLabelColor: colors.tertiaryText,
              labelStyle: text.mono(
                theme.textTheme.labelMedium,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
              tabs: const [
                Tab(text: 'POLLS'),
                Tab(text: 'PREDICT'),
                Tab(text: 'RECAP'),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _PollsTab(matchId: widget.matchId),
            _PredictTab(matchId: widget.matchId, match: match),
            _RecapTab(matchId: widget.matchId),
          ],
        ),
      ),
    );
  }
}
