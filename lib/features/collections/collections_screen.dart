import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/repositories/collect_repository.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/collect_group_cards.dart';
import '../../shared/widgets/screen_scaffold.dart';
import 'group_creation_platform.dart';

class CollectionsScreen extends ConsumerStatefulWidget {
  const CollectionsScreen({super.key});

  @override
  ConsumerState<CollectionsScreen> createState() => _CollectionsScreenState();
}

class GroupsSearchScreen extends ConsumerStatefulWidget {
  const GroupsSearchScreen({super.key});

  @override
  ConsumerState<GroupsSearchScreen> createState() => _GroupsSearchScreenState();
}

class _GroupsSearchScreenState extends ConsumerState<GroupsSearchScreen> {
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
    final profile = ref.watch(
      collectRepositoryProvider.select((state) => state.currentProfile),
    );
    final query = _query.trim().toLowerCase();
    final visibleCollections = [
      for (final collection in collections)
        if (_matchesQuery(collection, query)) collection,
    ]..sort((left, right) => _compareGroups(left, right, summaries));
    final showCreate = shouldShowGroupCreationEntryOnThisPlatform();

    return ScreenScaffold(
      title: 'Search groups',
      showHeader: false,
      compact: true,
      persistentPill: CollectTopChrome(
        avatarLabel: profile?.publicId,
        searchController: _search,
        searchLabel: 'Search groups',
        onSearchChanged: (value) => setState(() => _query = value),
        onAvatarTap: () => context.go('/settings/profile'),
        actions: [
          CollectTopChromeAction(
            icon: CollectIcons.qr,
            tooltip: 'Scan QR code',
            onPressed: () => context.go('/groups/scan'),
          ),
          if (showCreate)
            CollectTopChromeAction(
              icon: CollectIcons.add,
              tooltip: 'Create group',
              onPressed: () => context.go('/groups/create'),
            ),
        ],
      ),
      children: [
        const MinimalStatePanel(
          icon: CollectIcons.search,
          title: 'Find a group.',
          message: 'Search by group name, paste a group link, or scan a QR.',
          tone: CollectStatusTone.info,
          titleMaxLines: 2,
          messageMaxLines: 2,
          contentMaxWidth: 420,
        ),
        if (collections.isEmpty)
          Column(
            children: [
              const EmptyIllustrationState(
                icon: CollectIcons.collectionsOutline,
                title: 'No groups yet',
                message: 'Scan a QR or create a group to start.',
              ),
              CollectSpacing.gap16,
              _GroupEmptyActionRail(
                showCreate: showCreate,
                onScan: () => context.go('/groups/scan'),
                onCreate: () => context.go('/groups/create'),
              ),
            ],
          )
        else if (query.isEmpty)
          const InfoSecurityBanner(
            title: 'Start typing',
            message: 'Results appear here as you search.',
            tone: CollectStatusTone.info,
          )
        else if (visibleCollections.isEmpty)
          Column(
            children: [
              EmptySearchState(
                title: 'No groups found',
                message: 'Try another name or scan a QR code.',
                onClear: () => setState(() {
                  _search.clear();
                  _query = '';
                }),
              ),
              CollectSpacing.gap16,
              _GroupEmptyActionRail(
                showCreate: showCreate,
                onScan: () => context.go('/groups/scan'),
                onCreate: () => context.go('/groups/create'),
              ),
            ],
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
    final routeUri = _maybeRouteUri(context);
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
    final profile = ref.watch(
      collectRepositoryProvider.select((state) => state.currentProfile),
    );
    final paymentIntents = ref.watch(
      collectRepositoryProvider.select((state) => state.paymentIntents),
    );
    final pageTitle = showContributedOnly ? 'Supported groups' : 'Groups';
    final groupsTopChrome = CollectTopChrome(
      avatarLabel: profile?.publicId,
      searchController: _search,
      searchLabel: showContributedOnly ? 'Supported groups' : 'Search groups',
      onSearchChanged: (value) => setState(() => _query = value),
      onAvatarTap: () => context.go('/settings/profile'),
      hasUnread: paymentIntents.isNotEmpty,
      actions: [
        CollectTopChromeAction(
          icon: CollectIcons.qr,
          tooltip: 'Scan QR code',
          onPressed: () => context.go('/groups/scan'),
        ),
        if (showCreate)
          CollectTopChromeAction(
            icon: CollectIcons.add,
            tooltip: 'Create group',
            onPressed: () => context.go('/groups/create'),
          ),
      ],
    );
    if (collections.isEmpty) {
      return ScreenScaffold(
        title: 'Groups',
        showHeader: false,
        compact: true,
        persistentPill: groupsTopChrome,
        children: [
          SectionHeader(title: pageTitle),
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
      compact: true,
      persistentPill: groupsTopChrome,
      children: [
        SectionHeader(title: pageTitle),
        if (visibleCollections.isEmpty)
          Column(
            children: [
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
              ),
              if (!showContributedOnly) ...[
                CollectSpacing.gap16,
                _GroupEmptyActionRail(
                  showCreate: showCreate,
                  onScan: () => context.go('/groups/scan'),
                  onCreate: () => context.go('/groups/create'),
                ),
              ],
            ],
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

Uri _maybeRouteUri(BuildContext context) {
  try {
    return GoRouterState.of(context).uri;
  } on Object {
    return Uri(path: '/groups');
  }
}

bool _matchesQuery(CollectCollection collection, String query) {
  if (query.isEmpty) return true;
  return collection.title.toLowerCase().contains(query) ||
      collection.slug.toLowerCase().contains(query) ||
      collection.collectionType.label.toLowerCase().contains(query) ||
      collection.collectionType.shortPurpose.toLowerCase().contains(query) ||
      (collection.purposeLabel?.toLowerCase().contains(query) ?? false);
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
