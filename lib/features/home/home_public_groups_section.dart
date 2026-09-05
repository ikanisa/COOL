part of 'home_screen.dart';

// Both discovery and membership use the owner-reviewed card presentation.
// Joining changes eligibility and CTA semantics, never the design family.
class _HomeGroupsSection extends StatelessWidget {
  const _HomeGroupsSection({
    required this.title,
    required this.collections,
    required this.summaries,
    super.key,
  });

  final String title;
  final List<CollectCollection> collections;
  final Map<String, CollectionSummary> summaries;

  @override
  Widget build(BuildContext context) {
    if (collections.isEmpty) {
      return const SizedBox.shrink();
    }

    final visibleGroups = collections.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: title,
          actionLabel: 'View all',
          onAction: () => context.go('/groups'),
        ),
        CollectSpacing.gap12,
        LayoutBuilder(
          builder: (context, constraints) {
            // Match the Groups screen: full content width on phones, then
            // two equal columns on wider layouts. The page owns scrolling.
            final columns = constraints.maxWidth >= 640 ? 2 : 1;
            const gap = CollectSpacing.x3;
            final columnWidth =
                (constraints.maxWidth - (gap * (columns - 1))) / columns;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              clipBehavior: Clip.none,
              itemCount: visibleGroups.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: gap,
                mainAxisSpacing: gap,
                childAspectRatio: columnWidth / 220,
              ),
              itemBuilder: (context, index) {
                final collection = visibleGroups[index];
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
                    tooltip: _contributionLabel(collection),
                    onPressed: () =>
                        context.go('/groups/${collection.id}/contribute'),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  String _contributionLabel(CollectCollection collection) {
    return collection.isPublic && !collection.isCurrentUserMember
        ? 'Contribute & Join ${collection.title}'
        : 'Contribute to ${collection.title}';
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
        fixedSize: const Size.square(CollectSpacing.iconTarget),
        minimumSize: const Size.square(CollectSpacing.iconTarget),
        padding: EdgeInsets.zero,
      ),
      onPressed: onPressed,
      icon: const Icon(CollectIcons.donate),
    );
  }
}
