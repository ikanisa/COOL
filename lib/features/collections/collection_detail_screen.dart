import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/date_format.dart';
import '../../core/utils/money_format.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import 'group_empty_state.dart';
import 'group_share_service.dart';

class CollectionDetailScreen extends ConsumerWidget {
  const CollectionDetailScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(collectRepositoryProvider);
    final repo = ref.read(collectRepositoryProvider.notifier);
    final collection = repo.maybeCollectionById(collectionId);
    if (collection == null) return const MissingGroupStateScreen();
    final summary = repo.summaryFor(collectionId);
    final visibleContributions = repo
        .contributionsFor(collectionId)
        .take(8)
        .toList();
    final profile = state.currentProfile;
    final isAdmin = profile != null && collection.creatorUserId == profile.id;

    return ScreenScaffold(
      title: 'Collect',
      subtitle: profile?.publicId,
      showHeader: false,
      bottomAction: isAdmin
          ? null
          : CollectButton(
              label: collection.collectionType.contributionPrompt,
              icon: CollectIcons.donate,
              onPressed: () => context.go('/groups/$collectionId/contribute'),
              expand: true,
            ),
      children: [
        CollectPlainPageHeader(title: collection.title),
        _GroupHero(
          collectionId: collectionId,
          collection: collection,
          summary: summary,
          canManage: isAdmin,
        ),
        _GroupActionStrip(collectionId: collectionId, collection: collection),
        const SectionHeader(title: 'Activity'),
        if (visibleContributions.isEmpty)
          const EmptyIllustrationState(
            icon: CollectIcons.activity,
            title: 'No support yet',
            message:
                'Confirmed contributions will appear after MoMo SMS verification.',
          )
        else
          _ContributionTimeline(contributions: visibleContributions),
      ],
    );
  }
}

class _GroupHero extends StatelessWidget {
  const _GroupHero({
    required this.collectionId,
    required this.collection,
    required this.summary,
    required this.canManage,
  });

  final String collectionId;
  final CollectCollection collection;
  final CollectionSummary summary;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconForeground = isDark ? colors.onImagePrimary : colors.textPrimary;
    final iconFill = isDark
        ? colors.onImagePrimary.withValues(alpha: 0.12)
        : colors.actionColor.withValues(alpha: 0.12);
    final iconBorder = isDark
        ? colors.onImagePrimary.withValues(alpha: 0.18)
        : colors.actionColor.withValues(alpha: 0.20);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final titleSize = textScale > 1.25 ? 24.0 : 30.0;
    return CollectCard(
      emphasis: CollectCardEmphasis.glow,
      accentColor: colors.actionColor,
      padding: EdgeInsets.zero,
      backgroundGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          CollectColors.referencePaymentsPurpleDeep,
          Color.alphaBlend(
            colors.actionColor.withValues(alpha: isDark ? 0.18 : 0.12),
            CollectColors.referencePaymentsPurple,
          ),
          CollectColors.referenceContentDark,
        ],
        stops: const [0, 0.54, 1],
      ),
      child: ClipRRect(
        borderRadius: CollectRadius.cardLargeBorder,
        child: Stack(
          children: [
            Positioned(
              right: -42,
              top: -48,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.actionColor.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const SizedBox(width: 190, height: 190),
              ),
            ),
            Padding(
              padding: CollectSpacing.cardPaddingComfortable,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: iconFill,
                          borderRadius: CollectRadius.panelBorder,
                          border: Border.all(color: iconBorder),
                        ),
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: Icon(
                            CollectIcons.collections,
                            color: iconForeground,
                            size: 24,
                          ),
                        ),
                      ),
                      CollectSpacing.gapW12,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              collection.title,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    color: colors.onImagePrimary,
                                    fontSize: titleSize,
                                    fontWeight: FontWeight.w900,
                                    height: 1,
                                    letterSpacing: 0,
                                  ),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                            ),
                            CollectSpacing.gap8,
                            CollectionTypeBadge(
                              type: collection.collectionType,
                              compact: true,
                            ),
                          ],
                        ),
                      ),
                      if (canManage) ...[
                        CollectSpacing.gapW8,
                        Tooltip(
                          message: 'Group settings',
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: iconFill,
                              shape: BoxShape.circle,
                              border: Border.all(color: iconBorder),
                            ),
                            child: Material(
                              color: colors.transparent,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () =>
                                    context.go('/groups/$collectionId/manage'),
                                child: SizedBox.square(
                                  dimension: 44,
                                  child: Icon(
                                    CollectIcons.settings,
                                    size: 22,
                                    color: iconForeground,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  CollectSpacing.gap24,
                  _GroupStatsCard(
                    collectionId: collectionId,
                    totalRaised: summary.amountRaisedRwf,
                    participants: summary.supporterCount,
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

class _GroupStatsCard extends StatelessWidget {
  const _GroupStatsCard({
    required this.collectionId,
    required this.totalRaised,
    required this.participants,
  });

  final String collectionId;
  final int totalRaised;
  final int participants;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x1),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: _GroupStatMetric(
              value: formatRwf(totalRaised),
              icon: CollectIcons.money,
              tone: CollectStatusTone.success,
              primary: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CollectSpacing.x3),
            child: Container(
              width: 1,
              height: 72,
              color: colors.onImagePrimary.withValues(alpha: 0.16),
            ),
          ),
          Expanded(
            flex: 2,
            child: _GroupStatMetric(
              value: '$participants',
              icon: CollectIcons.people,
              tone: CollectStatusTone.info,
              onTap: () => context.go('/groups/$collectionId/members'),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupStatMetric extends StatelessWidget {
  const _GroupStatMetric({
    required this.value,
    required this.icon,
    required this.tone,
    this.primary = false,
    this.onTap,
  });

  final String value;
  final IconData icon;
  final CollectStatusTone tone;
  final bool primary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconForeground = colors.statusForeground(tone);
    final iconFill = isDark
        ? Color.alphaBlend(
            iconForeground.withValues(alpha: 0.16),
            CollectColors.referenceContentDark,
          )
        : colors.statusBackground(tone);
    final iconBorder = iconForeground.withValues(alpha: isDark ? 0.26 : 0.18);
    final amountColor = colors.onImagePrimary;
    final metric = Column(
      crossAxisAlignment: primary
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: iconFill,
            shape: BoxShape.circle,
            border: Border.all(color: iconBorder),
          ),
          child: SizedBox.square(
            dimension: primary ? 42 : 38,
            child: Icon(icon, color: iconForeground, size: primary ? 23 : 21),
          ),
        ),
        CollectSpacing.gap8,
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: primary ? Alignment.centerLeft : Alignment.center,
          child: Text(
            value,
            style: primary
                ? CollectTypography.amountHero(amountColor)
                : CollectTypography.amountHero(iconForeground),
          ),
        ),
      ],
    );
    if (onTap == null) return metric;
    return Tooltip(
      message: 'Open group members',
      child: Semantics(
        button: true,
        label: 'Open group members',
        child: InkWell(
          borderRadius: CollectRadius.mdBorder,
          onTap: onTap,
          child: metric,
        ),
      ),
    );
  }
}

class _GroupActionStrip extends ConsumerWidget {
  const _GroupActionStrip({
    required this.collectionId,
    required this.collection,
  });

  final String collectionId;
  final CollectCollection collection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = [
      _GroupActionButton(
        icon: CollectIcons.donate,
        tooltip: 'Contribute',
        onTap: () => context.go('/groups/$collectionId/contribute'),
      ),
      _GroupActionButton(
        icon: CollectIcons.ledger,
        tooltip: 'Activity',
        onTap: () => context.go('/groups/$collectionId/ledger'),
      ),
      _GroupActionButton(
        icon: CollectIcons.qr,
        tooltip: 'Group QR',
        onTap: () => context.go('/groups/$collectionId/share'),
      ),
      _GroupActionButton(
        icon: CollectIcons.share,
        tooltip: 'Share',
        onTap: () => shareGroupDeepLink(
          context: context,
          ref: ref,
          collection: collection,
        ),
      ),
    ];

    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: actions.length,
        separatorBuilder: (_, _) => CollectSpacing.gapW12,
        itemBuilder: (context, index) => actions[index],
      ),
    );
  }
}

class _GroupActionButton extends StatelessWidget {
  const _GroupActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? colors.onImagePrimary : colors.textPrimary;
    final fill = isDark
        ? CollectColors.referenceAssetNavy.withValues(alpha: 0.90)
        : colors.glassControl;
    final border = isDark
        ? colors.onImagePrimary.withValues(alpha: 0.14)
        : colors.glassBorder;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: tooltip,
        button: true,
        child: Material(
          color: fill,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: border),
                boxShadow: [
                  BoxShadow(
                    color: colors.shadowPaint.withValues(
                      alpha: isDark ? 0.18 : 0.08,
                    ),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: SizedBox.square(
                dimension: 64,
                child: Icon(icon, color: foreground, size: 27),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ContributionTimeline extends StatelessWidget {
  const _ContributionTimeline({required this.contributions});

  final List<Contribution> contributions;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < contributions.length; index++)
          _TimelineRow(contribution: contributions[index]),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.contribution});

  final Contribution contribution;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x2),
            child: CollectCard(
              padding: const EdgeInsets.all(CollectSpacing.x4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.statusBackground(
                                  CollectStatusTone.info,
                                ),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colors
                                      .statusForeground(CollectStatusTone.info)
                                      .withValues(alpha: 0.24),
                                ),
                              ),
                              child: SizedBox.square(
                                dimension: 40,
                                child: Icon(
                                  CollectIcons.profile,
                                  size: 21,
                                  color: colors.statusForeground(
                                    CollectStatusTone.info,
                                  ),
                                ),
                              ),
                            ),
                            CollectSpacing.gapW8,
                            Expanded(
                              child: Text(
                                compactCollectIdLabel(
                                  contribution.supporterLabel,
                                ).replaceFirst('#', ''),
                                style: Theme.of(context).textTheme.titleMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        CollectSpacing.gap4,
                        Padding(
                          padding: const EdgeInsets.only(left: 48),
                          child: Text(
                            formatCollectDateTime(contribution.createdAt),
                            style: Theme.of(context).textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  CollectSpacing.gapW8,
                  SizedBox(
                    width: 104,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            formatRwf(contribution.amountRwf),
                            style: CollectTypography.amountLarge(
                              colors.textPrimary,
                            ),
                          ),
                        ),
                        if (contribution.transactionId != null) ...[
                          CollectSpacing.gap8,
                          Icon(
                            CollectIcons.check,
                            size: 20,
                            color: colors.textSecondary,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
