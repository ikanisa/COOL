import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/date_format.dart';
import '../../core/utils/money_format.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/collect_data_load_failure.dart';
import '../../shared/widgets/collect_history_footer.dart';
import '../../shared/widgets/screen_scaffold.dart';

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
    final query = MemberHistoryQuery(
      collectionId: _collectionId,
      search: _query.trim().toLowerCase(),
    );
    final feed = ref.watch(memberHistoryProvider(query));
    final controller = ref.read(memberHistoryProvider(query).notifier);
    final visible = feed.page?.items ?? const <Contribution>[];
    final totals = feed.page?.totals ?? const <String, int>{};
    final total = formatCurrencyTotals(
      totals,
      separator: '\n',
      emptyCurrency: state.currentProfile?.isDiaspora == true ? 'EUR' : 'RWF',
    );
    final isInitialLoading =
        (feed.loading && feed.page == null) ||
        (state.isLoading &&
            state.collections.isEmpty &&
            state.contributions.isEmpty);

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
      onRefresh: () async {
        await ref.read(collectRepositoryProvider.notifier).loadInitial();
        if (mounted) {
          await ref.read(memberHistoryProvider(query).notifier).refresh();
        }
      },
      sliver: isInitialLoading || state.hasInitialLoadFailure || visible.isEmpty
          ? null
          : SliverMainAxisGroup(
              slivers: [
                CollectSliverCardList(
                  topSpacing: CollectSpacing.x3,
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final contribution = visible[index];
                    return ActivityFeedItem(
                      key: ValueKey(contribution.id),
                      title:
                          collectionsById[contribution.collectionId]?.title ??
                          'Group contribution',
                      amount: contribution.amountRwf,
                      currency: contribution.currency,
                      meta:
                          '${compactCollectIdLabel(contribution.supporterLabel)}'
                          ' · ${formatCollectDateTime(contribution.createdAt)}',
                      transactionId: contribution.transactionId,
                      tone: CollectStatusTone.success,
                      prioritizeContext: true,
                      onTap: () => context.go(
                        '/groups/${contribution.collectionId}/ledger',
                      ),
                    );
                  },
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    indent: 56,
                    color: context.collectColors.border.withValues(alpha: 0.48),
                  ),
                ),
                SliverToBoxAdapter(
                  child: CollectHistoryFooter(
                    feed: feed,
                    onMore: controller.loadMore,
                    onRefresh: controller.refresh,
                  ),
                ),
              ],
            ),
      children: [
        if (_searching)
          SearchWithClearField(
            controller: _search,
            focusNode: _searchFocus,
            label: 'Search group, Collect ID, or transaction',
            onChanged: (value) => setState(() => _query = value),
          ),
        ...(isInitialLoading
            ? const [
                CollectScreenLoadingState(
                  title: 'Loading activity',
                  message: 'Refreshing confirmed contribution records.',
                  icon: CollectIcons.activity,
                  skeletonCount: 3,
                ),
              ]
            : state.hasInitialLoadFailure ||
                  (feed.error != null && feed.page == null)
            ? [
                CollectDataLoadFailure(
                  onRetry: () async {
                    await ref
                        .read(collectRepositoryProvider.notifier)
                        .loadInitial();
                    if (mounted) {
                      await ref
                          .read(memberHistoryProvider(query).notifier)
                          .refresh();
                    }
                  },
                ),
              ]
            : [
                _ActivityTitleRow(
                  total: total,
                  count: feed.page?.totalCount ?? 0,
                  groupLabel: _selectedGroupLabel(collectionsById),
                ),
                if (visible.isEmpty && query.isDefault)
                  EmptyIllustrationState(
                    icon: CollectIcons.activity,
                    title: 'No activity yet',
                    message: state.currentProfile?.isRwanda == true
                        ? 'Confirmed MoMo contributions appear here.'
                        : 'Bank contributions appear here after statement reconciliation.',
                  )
                else if (visible.isEmpty)
                  EmptySearchState(
                    title: 'No matching activity',
                    message: 'Clear the search or group filter and try again.',
                    onClear: _clearFilters,
                  ),
              ]),
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

  final String total;
  final int count;
  final String groupLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = colors.textPrimary;
    final muted = colors.textSecondary;
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
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                '$groupLabel · $count',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: muted,
                  fontWeight: CollectTypography.weightSemibold,
                ),
                maxLines: largeText ? 2 : 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            CollectSpacing.gap4,
            Icon(CollectIcons.check, size: 14, color: muted),
          ],
        ),
      ],
    );
    final amount = Text(
      total,
      style: CollectTypography.amountCompact(foreground),
    );
    return Semantics(
      header: true,
      label: 'Activity, $groupLabel, $count confirmed, $total',
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
