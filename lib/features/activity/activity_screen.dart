import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/date_format.dart';
import '../../core/utils/money_format.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

const _activityBackdropLimit = 8;

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  String? _collectionId;
  bool _searching = false;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collectRepositoryProvider);
    final collectionsById = {
      for (final collection in state.collections) collection.id: collection,
    };
    final contributions = ref.watch(confirmedContributionActivityProvider);
    final query = _query.trim().toLowerCase();
    final visible = contributions.where((contribution) {
      if (_collectionId != null && contribution.collectionId != _collectionId) {
        return false;
      }
      if (query.isEmpty) return true;
      final groupTitle =
          collectionsById[contribution.collectionId]?.title ?? 'Group';
      return groupTitle.toLowerCase().contains(query) ||
          contribution.supporterLabel.toLowerCase().contains(query) ||
          (contribution.transactionId ?? '').toLowerCase().contains(query);
    }).toList();
    final total = visible.fold<int>(
      0,
      (sum, contribution) => sum + contribution.amountRwf,
    );
    final isInitialLoading =
        state.isLoading &&
        state.collections.isEmpty &&
        state.contributions.isEmpty;

    return ScreenScaffold(
      title: 'Activity',
      showHeader: false,
      compact: true,
      topChrome: CollectScreenTopChrome(
        avatarLabel: state.currentProfile?.publicId,
        avatarTooltip: 'Profile',
        searchLabel: 'Search activity',
        onAvatarTap: () => context.go('/settings'),
        onSearchTap: _beginSearch,
        actions: [
          CollectChromeAction(
            icon: CollectIcons.filter,
            tooltip: _collectionId == null ? 'Filter by group' : 'Group filter',
            onPressed: () => _showGroupFilter(state.collections),
          ),
        ],
      ),
      onRefresh: () =>
          ref.read(collectRepositoryProvider.notifier).loadInitial(),
      children: isInitialLoading
          ? const [
              CollectScreenLoadingState(
                title: 'Loading activity',
                message: 'Refreshing confirmed contribution records.',
                icon: CollectIcons.activity,
                skeletonCount: 3,
              ),
            ]
          : [
              _ActivityTitleRow(
                total: total,
                count: visible.length,
                groupLabel: _selectedGroupLabel(collectionsById),
              ),
              if (_searching)
                SearchWithClearField(
                  controller: _search,
                  focusNode: _searchFocus,
                  label: 'Search group, Collect ID, or transaction',
                  onChanged: (value) => setState(() => _query = value),
                ),
              if (contributions.isEmpty)
                const EmptyIllustrationState(
                  icon: CollectIcons.activity,
                  title: 'No activity yet',
                  message:
                      'Confirmed MoMo contributions will appear here after SMS verification.',
                )
              else if (visible.isEmpty)
                EmptySearchState(
                  title: 'No matching activity',
                  message: 'Clear the search or group filter and try again.',
                  onClear: _clearFilters,
                )
              else
                RepaintBoundary(
                  child: CollectCard(
                    emphasis: CollectCardEmphasis.flat,
                    blurBackground: visible.length <= _activityBackdropLimit,
                    child: Column(
                      children: [
                        for (
                          var index = 0;
                          index < visible.length;
                          index++
                        ) ...[
                          ActivityFeedItem(
                            title:
                                collectionsById[visible[index].collectionId]
                                    ?.title ??
                                'Group contribution',
                            amount: visible[index].amountRwf,
                            meta:
                                '${compactCollectIdLabel(visible[index].supporterLabel)}'
                                ' · ${formatCollectDateTime(visible[index].createdAt)}',
                            transactionId: visible[index].transactionId,
                            tone: CollectStatusTone.success,
                            onTap: () => context.go(
                              '/groups/${visible[index].collectionId}/ledger',
                            ),
                          ),
                          if (index != visible.length - 1)
                            Divider(
                              height: 1,
                              indent: 56,
                              color: context.collectColors.border.withValues(
                                alpha: 0.48,
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
    );
  }

  String _selectedGroupLabel(Map<String, CollectCollection> collectionsById) {
    final selected = _collectionId;
    if (selected == null) return 'All groups';
    return collectionsById[selected]?.title ?? 'Selected group';
  }

  void _beginSearch() {
    if (!_searching) {
      setState(() => _searching = true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _clearFilters() {
    setState(() {
      _search.clear();
      _query = '';
      _collectionId = null;
    });
  }

  void _showGroupFilter(List<CollectCollection> collections) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: context.collectColors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: CollectMotion.animationStyle(context),
      builder: (sheetContext) {
        return CollectBottomSheet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: 'Filter by group'),
              RadioGroup<String?>(
                groupValue: _collectionId,
                onChanged: (value) {
                  setState(() => _collectionId = value);
                  Navigator.of(sheetContext).pop();
                },
                child: Column(
                  children: [
                    const RadioListTile<String?>(
                      value: null,
                      title: Text('All groups'),
                    ),
                    for (final collection in collections)
                      RadioListTile<String?>(
                        value: collection.id,
                        title: Text(collection.title),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ActivityTitleRow extends StatelessWidget {
  const _ActivityTitleRow({
    required this.total,
    required this.count,
    required this.groupLabel,
  });

  final int total;
  final int count;
  final String groupLabel;

  @override
  Widget build(BuildContext context) {
    const foreground = CollectColors.brandPaper;
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Activity',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: foreground,
            fontWeight: CollectTypography.weightBold,
            letterSpacing: CollectTypography.trackingDefault,
          ),
        ),
        Text(
          '$groupLabel · $count confirmed',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: foreground.withValues(alpha: 0.74),
            fontWeight: CollectTypography.weightSemibold,
          ),
          maxLines: largeText ? 2 : 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
    final amount = Text(
      formatRwf(total),
      style: CollectTypography.amountCompact(foreground),
    );
    return Semantics(
      header: true,
      label: 'Activity, $groupLabel, $count confirmed, ${formatRwf(total)}',
      child: ExcludeSemantics(
        child: largeText
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, CollectSpacing.gap8, amount],
              )
            : Row(
                children: [
                  Expanded(child: title),
                  amount,
                ],
              ),
      ),
    );
  }
}
