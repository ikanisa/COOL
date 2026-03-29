import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/rs_tier_badge.dart';

import '../models/rs_models.dart';
import '../providers/member_registry_provider.dart';
import '../providers/rayon_sports_provider.dart';
import '../../../../shared/widgets/core_app_scaffold.dart';
import '../widgets/rayon_state_views.dart';
import '../../../../core/l10n/l10n.dart';

part '../widgets/member_registry_parts.dart';

class MemberRegistryScreen extends ConsumerStatefulWidget {
  const MemberRegistryScreen({super.key});

  @override
  ConsumerState<MemberRegistryScreen> createState() =>
      _MemberRegistryScreenState();
}

class _MemberRegistryScreenState extends ConsumerState<MemberRegistryScreen> {
  late final TextEditingController _searchController;
  String? _initializedPartnerId;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final partnerIdAsync = ref.watch(rayonPartnerIdProvider);
    final registryState = ref.watch(memberRegistryProvider);
    final registryNotifier = ref.read(memberRegistryProvider.notifier);

    return CoreAppScaffold(
      titleWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FAN REGISTRY',
            style: text.rayonCondensed(
              const TextStyle(fontSize: 28),
              fontWeight: FontWeight.w900,
              color: colors.primaryText,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'OFFICIAL GIKUNDIRO DATABASE',
            style: text.mono(
              theme.textTheme.labelSmall,
              fontWeight: FontWeight.w600,
              color: colors.secondaryText,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
      fallbackLocation: AppRoutes.rayonHome,
      scrollable: false,
      child: partnerIdAsync.when(
        data: (partnerId) {
          if (partnerId.isEmpty) {
            return RayonErrorView(
              message: 'Rayon Sports partner unavailable.',
              onRetry: _retryPartnerLookup,
            );
          }

          if (_initializedPartnerId != partnerId) {
            _initializedPartnerId = partnerId;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              registryNotifier.init(partnerId);
            });
          }

          final members = registryState.members;
          final topFan = registryState.topFan;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SearchBar(
                      controller: _searchController,
                      onChanged: registryNotifier.search,
                    ),
                    const SizedBox(height: CoolSpace.x4),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final filter
                              in MemberRegistryFilter.values) ...[
                            _TierChip(
                              label: filter.label,
                              isSelected:
                                  filter == registryState.filter,
                              onTap: () =>
                                  registryNotifier.selectFilter(filter),
                            ),
                            if (filter !=
                                MemberRegistryFilter.values.last)
                              const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: registryState.isLoading
                    ? const RayonInlineLoadingView(compact: true)
                    : registryState.error != null && members.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  registryState.error!,
                                  textAlign: TextAlign.center,
                                  style: text.rayon(
                                    theme.textTheme.bodyMedium,
                                    fontWeight: FontWeight.w600,
                                    color: colors.secondaryText,
                                  ),
                                ),
                                const SizedBox(height: CoolSpace.x3),
                                TextButton(
                                  onPressed: () =>
                                      registryNotifier.init(partnerId),
                                  child: Text(context.l10n.retry),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(
                              18, CoolSpace.x4, 18, 96,
                            ),
                            itemCount: _listItemCount(
                              members,
                              registryState,
                              showTopFan:
                                  registryState.filter ==
                                      MemberRegistryFilter.all &&
                                  topFan != null,
                            ),
                            itemBuilder: (context, index) {
                              if (members.isEmpty) {
                                return _EmptyRegistryState(
                                  query: registryState.query,
                                );
                              }

                              final showTopFan =
                                  registryState.filter ==
                                      MemberRegistryFilter.all &&
                                  topFan != null;

                              // Top Fan Spotlight section
                              if (showTopFan && index == 0) {
                                return _TopFanSpotlightSection(
                                  member: topFan,
                                );
                              }

                              // Supporter Rankings header
                              final headerIndex =
                                  showTopFan ? 1 : 0;
                              if (index == headerIndex) {
                                return _SupporterRankingsHeader(
                                  count: members.length,
                                );
                              }

                              // Member tiles
                              final memberOffset =
                                  (showTopFan ? 2 : 1);
                              final memberIndex =
                                  index - memberOffset;

                              if (memberIndex >= 0 &&
                                  memberIndex < members.length) {
                                return Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: 12,
                                  ),
                                  child: _RankedMemberTile(
                                    member: members[memberIndex],
                                    rank: memberIndex + 1,
                                  ),
                                );
                              }

                              // Load more
                              if (registryState.hasMore &&
                                  index ==
                                      members.length + memberOffset) {
                                return Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(
                                        0, 6, 0, 18,
                                      ),
                                  child: registryState.isLoadingMore
                                      ? const Center(
                                          child: Padding(
                                            padding:
                                                EdgeInsets.all(16),
                                            child:
                                                RayonInlineBusyIndicator(),
                                          ),
                                        )
                                      : _LoadMoreButton(
                                          visibleCount:
                                              members.length,
                                          onTap: registryNotifier
                                              .loadMore,
                                        ),
                                );
                              }

                              return const SizedBox.shrink();
                            },
                          ),
              ),
            ],
          );
        },
        loading: RayonLoadingView.new,
        error: (error, _) => RayonErrorView(
          message: error.toString(),
          onRetry: _retryPartnerLookup,
        ),
      ),
    );
  }

  void _retryPartnerLookup() {
    setState(() {
      _initializedPartnerId = null;
    });
    ref.invalidate(rayonPartnerIdProvider);
    ref.invalidate(memberRegistryProvider);
  }

  int _listItemCount(
    List<RsRegistryMember> members,
    MemberRegistryState state, {
    required bool showTopFan,
  }) {
    if (members.isEmpty) {
      return 1;
    }
    // top fan card + rankings header + members + load more
    final headerCount = showTopFan ? 2 : 1;
    return headerCount +
        members.length +
        (state.hasMore ? 1 : 0);
  }
}
