import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/date_format.dart';
import '../../core/utils/money_format.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import '../collections/group_creation_platform.dart';
import 'app_share_service.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collections = ref.watch(homeCollectionsProvider);
    final profile = ref.watch(
      collectRepositoryProvider.select((state) => state.currentProfile),
    );
    final paymentIntents = ref.watch(
      collectRepositoryProvider.select((state) => state.paymentIntents),
    );
    final contributedGroupCount = ref.watch(
      contributedCollectionIdsProvider.select((ids) => ids.length),
    );
    final summaries = ref.watch(collectionSummariesProvider);
    final raisedTotal = ref.watch(raisedTotalProvider);
    final contributions = ref.watch(
      collectRepositoryProvider.select((state) => state.contributions),
    );
    final showCreate = shouldShowGroupCreationEntryOnThisPlatform();
    return ScreenScaffold(
      title: 'Home',
      showHeader: false,
      compact: true,
      persistentPill: CollectTopChrome(
        avatarLabel: profile?.publicId,
        showSearch: false,
        onAvatarTap: () => context.go('/settings/profile'),
        hasUnread: paymentIntents.isNotEmpty,
        actions: [
          CollectTopChromeAction(
            icon: CollectIcons.pending,
            tooltip: 'Notifications',
            hasBadge: paymentIntents.isNotEmpty,
            onPressed: () => context.go('/notifications'),
          ),
        ],
      ),
      children: [
        _HomeTotalCollectedCard(
          totalAmount: raisedTotal,
          contributedGroupCount: contributedGroupCount,
          publicId: profile?.publicId,
          onContributedGroupsTap: () =>
              context.go('/groups?filter=contributed'),
        ),
        _HomeActionStrip(
          showCreate: showCreate,
          onCreate: () => context.go('/groups/create'),
        ),
        _PublicGroupsSection(collections: collections, summaries: summaries),
        const SectionHeader(title: 'My groups'),
        if (collections.isEmpty)
          const EmptyIllustrationState(
            icon: CollectIcons.collectionsOutline,
            title: 'No groups yet',
            message: 'Create a group or scan a group QR.',
          )
        else
          for (final collection in collections)
            GroupCard(
              collection: collection,
              summary:
                  summaries[collection.id] ??
                  const CollectionSummary(
                    amountRaisedRwf: 0,
                    supporterCount: 0,
                  ),
              onTap: () => context.go('/groups/${collection.id}'),
              variant: GroupCardVariant.visual,
              primaryAction: _HomeContributeIconButton(
                tooltip: 'Contribute',
                onPressed: () =>
                    context.go('/groups/${collection.id}/contribute'),
              ),
            ),
        const SectionHeader(title: 'Activity'),
        if (contributions.isEmpty)
          const EmptyIllustrationState(
            icon: CollectIcons.activity,
            title: 'No support yet',
            message: 'MoMo confirmations appear here.',
          )
        else
          CollectCard(
            child: Column(
              children: [
                for (final contribution in contributions.take(5))
                  ActivityFeedItem(
                    title: compactCollectIdLabel(contribution.supporterLabel),
                    amount: contribution.amountRwf,
                    meta: formatCollectDateTime(contribution.createdAt),
                    onTap: () => context.go(
                      '/groups/${contribution.collectionId}/ledger',
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _HomeContributeIconButton extends StatelessWidget {
  const _HomeContributeIconButton({
    required this.tooltip,
    required this.onPressed,
  });

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? colors.onImagePrimary : colors.textPrimary;
    final background = isDark
        ? colors.onImagePrimary.withValues(alpha: 0.16)
        : colors.textPrimary.withValues(alpha: 0.10);
    final border = isDark
        ? colors.onImagePrimary.withValues(alpha: 0.18)
        : colors.textPrimary.withValues(alpha: 0.12);
    return IconButton.filledTonal(
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        side: BorderSide(color: border),
        fixedSize: const Size(42, 42),
        minimumSize: const Size(42, 42),
        padding: EdgeInsets.zero,
      ),
      onPressed: onPressed,
      icon: const Icon(CollectIcons.donate),
    );
  }
}

class _HomeTotalCollectedCard extends StatelessWidget {
  const _HomeTotalCollectedCard({
    required this.totalAmount,
    required this.contributedGroupCount,
    required this.onContributedGroupsTap,
    this.publicId,
  });

  final int totalAmount;
  final int contributedGroupCount;
  final VoidCallback onContributedGroupsTap;
  final String? publicId;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? colors.onImagePrimary : colors.surfaceReadable;
    final mutedForeground = foreground.withValues(alpha: 0.74);
    final heroGradient = isDark
        ? const LinearGradient(
            colors: [
              CollectColors.referenceAccountBlue,
              CollectColors.referenceAccountBlueDeep,
              CollectColors.referenceAccountNavyDeep,
              CollectColors.referencePaymentsPurpleDeep,
            ],
            stops: [0, 0.34, 0.74, 1],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : LinearGradient(
            colors: [
              colors.textPrimary,
              colors.periwinklePaint,
              colors.actionColor,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: heroGradient,
        boxShadow: [
          BoxShadow(
            color: CollectColors.inkPrimary.withValues(alpha: 0.24),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          children: [
            Positioned(
              right: -48,
              top: -58,
              child: _HomeAngledPanel(
                color: foreground.withValues(alpha: isDark ? 0.08 : 0.14),
                width: 180,
                height: 112,
                angle: -0.24,
              ),
            ),
            Positioned(
              left: -58,
              bottom: -72,
              child: _HomeAngledPanel(
                color: colors.mintPaint.withValues(alpha: 0.18),
                width: 190,
                height: 96,
                angle: 0.18,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      const CollectBrandMark(
                        compact: true,
                        framed: false,
                        width: 104,
                        height: 30,
                      ),
                      const Spacer(),
                      if (publicId != null)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: foreground.withValues(alpha: 0.16),
                            borderRadius: CollectRadius.pillBorder,
                            border: Border.all(
                              color: foreground.withValues(alpha: 0.22),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            child: Text(
                              publicId!,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: foreground,
                                    fontWeight: FontWeight.w900,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                    ],
                  ),
                  CollectSpacing.gap24,
                  Text(
                    'TOTAL COLLECTED',
                    style: CollectTypography.eyebrowLabel(mutedForeground),
                  ),
                  CollectSpacing.gap8,
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      formatRwf(totalAmount),
                      style: CollectTypography.amountDisplay(
                        foreground,
                      ).copyWith(fontSize: 52, height: 0.98),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Tooltip(
                    message: 'Supported groups',
                    child: Semantics(
                      button: true,
                      label: contributedGroupCount == 1
                          ? '1 supported group'
                          : '$contributedGroupCount supported groups',
                      child: Material(
                        color: colors.transparent,
                        borderRadius: CollectRadius.pillBorder,
                        child: InkWell(
                          key: const Key('home_supported_groups_chip'),
                          borderRadius: CollectRadius.pillBorder,
                          onTap: onContributedGroupsTap,
                          child: Ink(
                            decoration: BoxDecoration(
                              color: foreground.withValues(alpha: 0.16),
                              borderRadius: CollectRadius.pillBorder,
                              border: Border.all(
                                color: foreground.withValues(alpha: 0.12),
                              ),
                            ),
                            child: ExcludeSemantics(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 9,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      CollectIcons.collections,
                                      color: foreground,
                                      size: 18,
                                    ),
                                    CollectSpacing.gapW8,
                                    Text(
                                      '$contributedGroupCount',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            color: foreground,
                                            fontWeight: FontWeight.w900,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeAngledPanel extends StatelessWidget {
  const _HomeAngledPanel({
    required this.color,
    required this.width,
    required this.height,
    required this.angle,
  });

  final Color color;
  final double width;
  final double height;
  final double angle;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(24),
        ),
        child: SizedBox(width: width, height: height),
      ),
    );
  }
}

class _PublicGroupsSection extends StatelessWidget {
  const _PublicGroupsSection({
    required this.collections,
    required this.summaries,
  });

  final List<CollectCollection> collections;
  final Map<String, CollectionSummary> summaries;

  @override
  Widget build(BuildContext context) {
    if (collections.isEmpty) {
      return const SizedBox.shrink();
    }

    final publicGroups = collections.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Featured Groups',
          actionLabel: 'View all',
          onAction: () => context.go('/groups'),
        ),
        CollectSpacing.gap12,
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            if (wide) {
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: publicGroups.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: CollectSpacing.x3,
                  crossAxisSpacing: CollectSpacing.x3,
                  childAspectRatio: 1.24,
                ),
                itemBuilder: (context, index) {
                  final collection = publicGroups[index];
                  return GroupCard(
                    collection: collection,
                    summary:
                        summaries[collection.id] ??
                        const CollectionSummary(
                          amountRaisedRwf: 0,
                          supporterCount: 0,
                        ),
                    variant: GroupCardVariant.publicDiscovery,
                    onTap: () => context.go('/groups/${collection.id}'),
                    primaryAction: _HomeContributeIconButton(
                      tooltip: 'Contribute',
                      onPressed: () =>
                          context.go('/groups/${collection.id}/contribute'),
                    ),
                  );
                },
              );
            }
            return SizedBox(
              height: 204,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: EdgeInsets.zero,
                itemCount: publicGroups.length,
                separatorBuilder: (_, _) => CollectSpacing.gapW12,
                itemBuilder: (context, index) {
                  final collection = publicGroups[index];
                  return SizedBox(
                    width: 274,
                    child: GroupCard(
                      collection: collection,
                      summary:
                          summaries[collection.id] ??
                          const CollectionSummary(
                            amountRaisedRwf: 0,
                            supporterCount: 0,
                          ),
                      variant: GroupCardVariant.publicDiscovery,
                      onTap: () => context.go('/groups/${collection.id}'),
                      primaryAction: _HomeContributeIconButton(
                        tooltip: 'Contribute',
                        onPressed: () =>
                            context.go('/groups/${collection.id}/contribute'),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}

class _HomeActionStrip extends ConsumerWidget {
  const _HomeActionStrip({required this.onCreate, required this.showCreate});

  final VoidCallback onCreate;
  final bool showCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = [
      if (showCreate)
        _HomeActionItem(
          icon: CollectIcons.add,
          label: 'Create',
          onTap: onCreate,
        ),
      _HomeActionItem(
        icon: CollectIcons.people,
        label: 'Join',
        onTap: () => context.go('/groups'),
      ),
      _HomeActionItem(
        icon: CollectIcons.qr,
        label: 'Scan QR',
        onTap: () => context.go('/groups/scan'),
      ),
      _HomeActionItem(
        icon: CollectIcons.share,
        label: 'Share',
        onTap: () => shareCollectApp(context: context, ref: ref),
      ),
    ];

    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return SizedBox(
      height: textScale > 1.6 ? 124 : (textScale > 1.3 ? 116 : 78),
      child: Row(
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            Expanded(child: actions[index]),
            if (index != actions.length - 1) CollectSpacing.gapW8,
          ],
        ],
      ),
    );
  }
}

class _HomeActionItem extends StatelessWidget {
  const _HomeActionItem({
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
    final textScale = MediaQuery.textScalerOf(context).scale(1);
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
              SizedBox(height: textScale > 1.3 ? 4 : 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: textScale > 1.3 ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
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
