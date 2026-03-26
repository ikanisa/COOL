import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/rs_tier_badge.dart';
import '../../../../shared/widgets/vehicle_chip.dart';
import '../models/rs_models.dart';
import '../../providers/member_registry_provider.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../../../shared/widgets/core_app_scaffold.dart';
import '../../widgets/rayon_state_views.dart';
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
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final partnerIdAsync = ref.watch(rayonPartnerIdProvider);
    final registryState = ref.watch(memberRegistryProvider);
    final registryNotifier = ref.read(memberRegistryProvider.notifier);

    return CoreAppScaffold(
      title: context.l10n.memberRegistry,
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

          // Initialize pagination with the partner ID on first build.
          if (_initializedPartnerId != partnerId) {
            _initializedPartnerId = partnerId;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              registryNotifier.init(partnerId);
            });
          }

          final members = registryState.members;
          final topFan = registryState.topFan;

          return Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RegistryCommandCard(
                  visibleCount: members.length,
                  activeFilter: registryState.filter,
                  topFan: topFan,
                  query: registryState.query,
                  hasMore: registryState.hasMore,
                  onFilterSelected: registryNotifier.selectFilter,
                ),
                SizedBox(height: space.x3),
                _SearchBar(
                  controller: _searchController,
                  onChanged: registryNotifier.search,
                ),
                SizedBox(height: space.x3),
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
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: _listItemCount(
                            members,
                            registryState,
                            showTopFanCard:
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

                            final showTopFanCard =
                                registryState.filter ==
                                    MemberRegistryFilter.all &&
                                topFan != null;
                            final memberOffset = showTopFanCard ? 1 : 0;

                            if (showTopFanCard && index == 0) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 18),
                                child: _TopFanSpotlight(member: topFan),
                              );
                            }

                            if (index < members.length + memberOffset) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _MemberListTile(
                                  member: members[index - memberOffset],
                                ),
                              );
                            }

                            if (registryState.hasMore &&
                                index == members.length + memberOffset) {
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(0, 6, 0, 18),
                                child: registryState.isLoadingMore
                                    ? const Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(16),
                                          child: RayonInlineBusyIndicator(),
                                        ),
                                      )
                                    : _LoadMoreButton(
                                        visibleCount: members.length,
                                        onTap: registryNotifier.loadMore,
                                      ),
                              );
                            }

                            if (index ==
                                members.length +
                                    memberOffset +
                                    (registryState.hasMore ? 1 : 0)) {
                              return const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: _TierLegendCard(),
                              );
                            }

                            return const SizedBox.shrink();
                          },
                        ),
                ),
              ],
            ),
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
    required bool showTopFanCard,
  }) {
    if (members.isEmpty) {
      return 1;
    }
    return members.length +
        (state.hasMore ? 1 : 0) +
        1 +
        (showTopFanCard ? 1 : 0);
  }
}
