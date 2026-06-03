import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/date_format.dart';
import '../../core/utils/money_format.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class CollectionDetailScreen extends ConsumerStatefulWidget {
  const CollectionDetailScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  ConsumerState<CollectionDetailScreen> createState() =>
      _CollectionDetailScreenState();
}

class _CollectionDetailScreenState
    extends ConsumerState<CollectionDetailScreen> {
  bool _mineOnly = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collectRepositoryProvider);
    final repo = ref.read(collectRepositoryProvider.notifier);
    final collection = repo.collectionById(widget.collectionId);
    final summary = repo.summaryFor(widget.collectionId);
    final allContributions = repo.contributionsFor(widget.collectionId);
    final profile = state.currentProfile;
    final isAdmin = profile != null && collection.creatorUserId == profile.id;
    final myLabel = profile == null ? null : 'Collect ID ${profile.publicId}';
    final visibleContributions =
        (_mineOnly && myLabel != null
                ? allContributions.where(
                    (item) => item.supporterLabel == myLabel,
                  )
                : allContributions)
            .take(8)
            .toList();

    return ScreenScaffold(
      title: isAdmin ? 'Group admin' : 'Group',
      subtitle: isAdmin ? 'Settings and activity.' : 'Contribute and activity.',
      actions: [
        IconButton.filledTonal(
          tooltip: 'Share',
          onPressed: () => context.go('/groups/${widget.collectionId}/share'),
          icon: const Icon(CollectIcons.share),
        ),
        if (isAdmin)
          IconButton.filledTonal(
            tooltip: 'Group settings',
            onPressed: () =>
                context.go('/groups/${widget.collectionId}/manage'),
            icon: const Icon(CollectIcons.admin),
          ),
      ],
      children: [
        _GroupHero(
          collection: collection,
          summary: summary,
          canManage: isAdmin,
          onShare: () => context.go('/groups/${widget.collectionId}/share'),
          onManage: () => context.go('/groups/${widget.collectionId}/manage'),
        ),
        _GroupActionStrip(
          collectionId: widget.collectionId,
          canManage: isAdmin,
        ),
        if (isAdmin)
          _AdminToolsPanel(collectionId: widget.collectionId)
        else
          _MemberSupportPanel(collectionId: widget.collectionId),
        _ContributionSectionHeader(
          mineOnly: _mineOnly,
          onAll: () => setState(() => _mineOnly = false),
          onMine: () => setState(() => _mineOnly = true),
        ),
        if (visibleContributions.isEmpty)
          EmptyIllustrationState(
            icon: CollectIcons.activity,
            title: _mineOnly ? 'No payments from you yet' : 'No support yet',
            message: _mineOnly
                ? 'Your confirmed MoMo payments will appear here.'
                : 'Confirmed contributions will appear after MoMo SMS verification.',
          )
        else
          _ContributionTimeline(
            contributions: visibleContributions,
            currentPublicId: profile?.publicId,
          ),
        CollectButton(
          label: isAdmin ? 'Open group settings' : 'Contribute with MoMo',
          icon: isAdmin ? CollectIcons.admin : CollectIcons.momo,
          onPressed: () => context.go(
            isAdmin
                ? '/groups/${widget.collectionId}/manage'
                : '/groups/${widget.collectionId}/contribute',
          ),
          expand: true,
        ),
      ],
    );
  }
}

class _GroupHero extends StatelessWidget {
  const _GroupHero({
    required this.collection,
    required this.summary,
    required this.canManage,
    required this.onShare,
    required this.onManage,
  });

  final CollectCollection collection;
  final CollectionSummary summary;
  final bool canManage;
  final VoidCallback onShare;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    collection.title,
                    style: Theme.of(context).textTheme.headlineMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  CollectSpacing.gap8,
                  Text(
                    collection.description,
                    style: Theme.of(context).textTheme.bodyLarge,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            CollectSpacing.gapW12,
            IconButton.filledTonal(
              tooltip: 'Share group',
              onPressed: onShare,
              icon: const Icon(CollectIcons.share),
            ),
            if (canManage) ...[
              CollectSpacing.gapW8,
              IconButton.filledTonal(
                tooltip: 'Group settings',
                onPressed: onManage,
                icon: const Icon(CollectIcons.admin),
              ),
            ],
          ],
        ),
        CollectSpacing.gap20,
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;
            final totalCard = _GroupStatCard(
              label: 'Total collected',
              value: formatRwf(summary.amountRaisedRwf),
              icon: CollectIcons.money,
              tone: CollectStatusTone.success,
              emphasize: true,
            );
            final participantsCard = _GroupStatCard(
              label: 'Participants',
              value: '${summary.supporterCount}',
              icon: CollectIcons.people,
              tone: CollectStatusTone.info,
            );
            if (compact) {
              return Column(
                children: [totalCard, CollectSpacing.gap12, participantsCard],
              );
            }
            return Row(
              children: [
                Expanded(child: totalCard),
                CollectSpacing.gapW12,
                Expanded(child: participantsCard),
              ],
            );
          },
        ),
        CollectSpacing.gap16,
        CollectCard(
          emphasis: CollectCardEmphasis.flat,
          child: Row(
            children: [
              Icon(CollectIcons.check, color: colors.success),
              CollectSpacing.gapW12,
              Expanded(
                child: Text(
                  'Receiver verified: ${collection.receiverDisplayLabel}',
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Copy group code',
                onPressed: () => copyToClipboard(
                  context,
                  collection.slug,
                  message: 'Group code copied.',
                ),
                icon: const Icon(CollectIcons.copy),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GroupStatCard extends StatelessWidget {
  const _GroupStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final CollectStatusTone tone;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return CollectCard(
      padding: const EdgeInsets.all(CollectSpacing.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: colors.statusForeground(tone)),
              CollectSpacing.gapW8,
              Text(
                label.toUpperCase(),
                style: CollectTypography.eyebrowLabel(colors.textSecondary),
              ),
            ],
          ),
          CollectSpacing.gap16,
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: emphasize
                  ? CollectTypography.amountDisplay(colors.textPrimary)
                  : CollectTypography.amountHero(colors.info),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupActionStrip extends StatelessWidget {
  const _GroupActionStrip({
    required this.collectionId,
    required this.canManage,
  });

  final String collectionId;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _GroupActionButton(
        icon: CollectIcons.momo,
        label: 'Contribute',
        onTap: () => context.go('/groups/$collectionId/contribute'),
        highlighted: !canManage,
      ),
      _GroupActionButton(
        icon: CollectIcons.ledger,
        label: 'Activity',
        onTap: () => context.go('/groups/$collectionId/ledger'),
      ),
      _GroupActionButton(
        icon: CollectIcons.share,
        label: 'Share',
        onTap: () => context.go('/groups/$collectionId/share'),
      ),
      if (canManage)
        _GroupActionButton(
          icon: CollectIcons.admin,
          label: 'Settings',
          onTap: () => context.go('/groups/$collectionId/manage'),
          highlighted: true,
        ),
    ];

    return SizedBox(
      height: 88,
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
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = highlighted ? Colors.white : colors.textPrimary;
    return Material(
      color: highlighted ? colors.actionCrimson : colors.surfaceRaised,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 126,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foreground, size: 28),
              CollectSpacing.gap8,
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminToolsPanel extends StatelessWidget {
  const _AdminToolsPanel({required this.collectionId});

  final String collectionId;

  @override
  Widget build(BuildContext context) {
    return CollectCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Admin tools', style: Theme.of(context).textTheme.titleLarge),
          CollectSpacing.gap12,
          CollectListTile(
            leading: CollectIcons.admin,
            title: 'Group settings',
            subtitle: 'Receiver, members, and owner controls.',
            onTap: () => context.go('/groups/$collectionId/manage'),
          ),
          CollectListTile(
            leading: CollectIcons.people,
            title: 'Members',
            subtitle: 'Collect IDs and roles.',
            onTap: () => context.go('/groups/$collectionId/members'),
          ),
          CollectListTile(
            leading: CollectIcons.momo,
            title: 'Receiver',
            subtitle: 'MoMo account setup.',
            onTap: () => context.go('/groups/$collectionId/owner/receiver'),
          ),
        ],
      ),
    );
  }
}

class _MemberSupportPanel extends StatelessWidget {
  const _MemberSupportPanel({required this.collectionId});

  final String collectionId;

  @override
  Widget build(BuildContext context) {
    return CollectButton(
      label: 'Support this group',
      icon: CollectIcons.momo,
      onPressed: () => context.go('/groups/$collectionId/contribute'),
      expand: true,
    );
  }
}

class _ContributionSectionHeader extends StatelessWidget {
  const _ContributionSectionHeader({
    required this.mineOnly,
    required this.onAll,
    required this.onMine,
  });

  final bool mineOnly;
  final VoidCallback onAll;
  final VoidCallback onMine;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Activity'),
        CollectSpacing.gap12,
        Row(
          children: [
            Expanded(
              child: _ContributionTab(
                label: 'All contributions',
                selected: !mineOnly,
                onTap: onAll,
              ),
            ),
            CollectSpacing.gapW12,
            Expanded(
              child: _ContributionTab(
                label: 'My payments',
                selected: mineOnly,
                onTap: onMine,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ContributionTab extends StatelessWidget {
  const _ContributionTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Material(
      color: selected ? colors.textPrimary : colors.surfaceMuted,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CollectSpacing.x4,
            vertical: CollectSpacing.x3,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected ? colors.surface : colors.textSecondary,
              fontWeight: FontWeight.w800,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

class _ContributionTimeline extends StatelessWidget {
  const _ContributionTimeline({
    required this.contributions,
    required this.currentPublicId,
  });

  final List<Contribution> contributions;
  final String? currentPublicId;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < contributions.length; index++)
          _TimelineRow(
            contribution: contributions[index],
            isFirst: index == 0,
            isLast: index == contributions.length - 1,
            isMine:
                currentPublicId != null &&
                contributions[index].supporterLabel.endsWith(currentPublicId!),
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.contribution,
    required this.isFirst,
    required this.isLast,
    required this.isMine,
  });

  final Contribution contribution;
  final bool isFirst;
  final bool isLast;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final dotColor = isFirst || isMine ? colors.actionCrimson : colors.border;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 54,
          child: Column(
            children: [
              Expanded(
                child: Container(
                  width: 1,
                  color: isFirst
                      ? Colors.transparent
                      : colors.border.withValues(alpha: 0.6),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.surface, width: 5),
                ),
                child: const SizedBox(width: 24, height: 24),
              ),
              Expanded(
                child: Container(
                  width: 1,
                  color: isLast
                      ? Colors.transparent
                      : colors.border.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
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
                        Text(
                          'ID: ${compactCollectIdLabel(contribution.supporterLabel).replaceFirst('#', '')}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        CollectSpacing.gap8,
                        Row(
                          children: [
                            Icon(
                              CollectIcons.check,
                              size: 18,
                              color: colors.textSecondary,
                            ),
                            CollectSpacing.gapW8,
                            Text(
                              'CONFIRMED',
                              style: CollectTypography.eyebrowLabel(
                                colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        CollectSpacing.gap4,
                        Text(
                          formatCollectDateTime(contribution.createdAt),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatRwf(contribution.amountRwf),
                        style: CollectTypography.amountLarge(
                          colors.textPrimary,
                        ),
                      ),
                      if (contribution.transactionId != null) ...[
                        CollectSpacing.gap8,
                        Text(
                          contribution.transactionId!,
                          style: CollectTypography.transactionMeta(
                            colors.textMuted,
                          ),
                        ),
                      ],
                    ],
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
