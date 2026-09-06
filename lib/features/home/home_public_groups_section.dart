part of 'home_screen.dart';

// Both discovery and membership use the owner-reviewed card presentation.
// Joining changes eligibility and CTA semantics, never the design family.
class _HomeGroupsSection extends StatelessWidget {
  const _HomeGroupsSection({
    required this.title,
    required this.collections,
    required this.summaries,
    this.groupsRoute = '/groups',
    this.showWhenEmpty = false,
    this.isLoading = false,
    this.emptyMessage = '',
    super.key,
  });

  final String title;
  final List<CollectCollection> collections;
  final Map<String, CollectionSummary> summaries;
  final String groupsRoute;
  final bool showWhenEmpty;
  final bool isLoading;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (collections.isEmpty && !showWhenEmpty) {
      return const SizedBox.shrink();
    }

    final visibleGroups = collections.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: title,
          actionLabel: 'View all',
          onAction: () => context.go(groupsRoute),
        ),
        CollectSpacing.gap12,
        if (isLoading)
          const LoadingSkeleton.groupCard(
            semanticsLabel: 'Loading featured groups',
          )
        else if (visibleGroups.isEmpty)
          Text(
            emptyMessage,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.collectColors.textSecondary,
            ),
          )
        else
          GroupCardLayout(
            itemCount: visibleGroups.length,
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
    return GroupCardActionButton(tooltip: tooltip, onPressed: onPressed);
  }
}
