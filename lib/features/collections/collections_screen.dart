import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/repositories/collect_repository.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import 'group_creation_platform.dart';

class CollectionsScreen extends ConsumerStatefulWidget {
  const CollectionsScreen({super.key});

  @override
  ConsumerState<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends ConsumerState<CollectionsScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final collections = ref.watch(
      collectRepositoryProvider.select((state) => state.collections),
    );
    final summaries = ref.watch(collectionSummariesProvider);
    final contributedCollectionIds = ref.watch(
      contributedCollectionIdsProvider,
    );
    final routeUri = GoRouterState.of(context).uri;
    final showContributedOnly =
        routeUri.queryParameters['filter'] == 'contributed';
    final query = _query.trim().toLowerCase();
    final visibleCollections = [
      for (final collection in collections)
        if (_matchesQuery(collection, query) &&
            (!showContributedOnly ||
                contributedCollectionIds.contains(collection.id)))
          collection,
    ]..sort((left, right) => _compareGroups(left, right, summaries));
    final showCreate = shouldShowGroupCreationEntryOnThisPlatform();
    if (collections.isEmpty) {
      return ScreenScaffold(
        title: 'Groups',
        showHeader: false,
        children: [
          _GroupsPageHeading(
            title: 'Groups',
            searchController: _search,
            searchLabel: 'Search groups',
            onSearchChanged: (value) => setState(() => _query = value),
          ),
          const EmptyIllustrationState(
            icon: CollectIcons.collectionsOutline,
            title: 'No groups yet',
            message: 'Scan a group QR or create one on Android.',
          ),
          _GroupEmptyActionRail(
            showCreate: showCreate,
            onScan: () => context.go('/groups/scan'),
            onCreate: () => context.go('/groups/create'),
          ),
        ],
      );
    }
    return ScreenScaffold(
      title: 'Groups',
      showHeader: false,
      children: [
        _GroupsPageHeading(
          title: showContributedOnly ? 'Supported groups' : 'Groups',
          searchController: _search,
          searchLabel: showContributedOnly
              ? 'Supported groups'
              : 'Search groups',
          onSearchChanged: (value) => setState(() => _query = value),
        ),
        if (visibleCollections.isEmpty)
          EmptySearchState(
            title: showContributedOnly
                ? 'No supported groups'
                : 'No groups found',
            message: showContributedOnly
                ? 'Groups you support will appear here.'
                : 'No group matches this search.',
            onClear: () => setState(() {
              if (showContributedOnly && query.isEmpty) {
                context.go('/groups');
              } else {
                _search.clear();
                _query = '';
              }
            }),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 640 ? 2 : 1;
              const gap = CollectSpacing.x3;
              final columnWidth =
                  (constraints.maxWidth - (gap * (columns - 1))) / columns;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                clipBehavior: Clip.none,
                itemCount: visibleCollections.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: gap,
                  mainAxisSpacing: gap,
                  childAspectRatio: columnWidth / 220,
                ),
                itemBuilder: (context, index) {
                  final collection = visibleCollections[index];
                  return GroupCard(
                    collection: collection,
                    summary:
                        summaries[collection.id] ??
                        const CollectionSummary(
                          amountRaisedRwf: 0,
                          supporterCount: 0,
                        ),
                    variant: GroupCardVariant.visual,
                    onTap: () => context.go('/groups/${collection.id}'),
                  );
                },
              );
            },
          ),
      ],
    );
  }
}

class _GroupsPageHeading extends StatelessWidget {
  const _GroupsPageHeading({
    required this.title,
    required this.searchController,
    required this.searchLabel,
    required this.onSearchChanged,
  });

  final String title;
  final TextEditingController searchController;
  final String searchLabel;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: colors.onImagePrimary,
            fontWeight: FontWeight.w900,
            height: 1,
            letterSpacing: 0,
          ),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        ),
        CollectSpacing.gap16,
        SearchWithClearField(
          controller: searchController,
          label: searchLabel,
          onChanged: onSearchChanged,
        ),
      ],
    );
  }
}

class _GroupEmptyActionRail extends StatelessWidget {
  const _GroupEmptyActionRail({
    required this.showCreate,
    required this.onScan,
    required this.onCreate,
  });

  final bool showCreate;
  final VoidCallback onScan;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _GroupEmptyActionItem(
        icon: CollectIcons.qr,
        label: 'Scan',
        onTap: onScan,
      ),
      if (showCreate)
        _GroupEmptyActionItem(
          icon: CollectIcons.add,
          label: 'Create group',
          onTap: onCreate,
        ),
    ];

    return SizedBox(
      height: 78,
      child: Row(
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            Expanded(child: actions[index]),
            if (index != actions.length - 1) CollectSpacing.gapW12,
          ],
        ],
      ),
    );
  }
}

class _GroupEmptyActionItem extends StatelessWidget {
  const _GroupEmptyActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? colors.onImagePrimary : colors.surfaceReadable;
    final iconFill = isDark
        ? CollectColors.inkPrimary.withValues(alpha: 0.92)
        : colors.textPrimary.withValues(alpha: 0.88);
    final iconBorder = foreground.withValues(alpha: isDark ? 0.22 : 0.20);

    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: CollectRadius.pillBorder,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: iconFill,
                  shape: BoxShape.circle,
                  border: Border.all(color: iconBorder),
                ),
                child: SizedBox.square(
                  dimension: 52,
                  child: Icon(icon, color: foreground, size: 23),
                ),
              ),
              CollectSpacing.gap4,
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _matchesQuery(CollectCollection collection, String query) {
  if (query.isEmpty) return true;
  return collection.title.toLowerCase().contains(query) ||
      collection.slug.toLowerCase().contains(query);
}

int _compareGroups(
  CollectCollection left,
  CollectCollection right,
  Map<String, CollectionSummary> summaries,
) {
  final leftSummary =
      summaries[left.id] ??
      const CollectionSummary(amountRaisedRwf: 0, supporterCount: 0);
  final rightSummary =
      summaries[right.id] ??
      const CollectionSummary(amountRaisedRwf: 0, supporterCount: 0);
  final result = rightSummary.amountRaisedRwf.compareTo(
    leftSummary.amountRaisedRwf,
  );
  if (result != 0) return result;
  return left.title.toLowerCase().compareTo(right.title.toLowerCase());
}
