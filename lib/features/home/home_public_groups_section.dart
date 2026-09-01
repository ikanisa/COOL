part of 'home_screen.dart';

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
          title: 'Public sponsored groups',
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
                      tooltip: 'View group',
                      onPressed: () => context.go('/groups/${collection.id}'),
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
                        tooltip: 'View group',
                        onPressed: () => context.go('/groups/${collection.id}'),
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
      icon: const Icon(CollectIcons.arrowForward),
    );
  }
}
