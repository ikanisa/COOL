part of 'collect_group_cards.dart';

/// Shared by Home and Groups. Content can grow without a fixed grid row
/// clipping enlarged text, long group names or additional currency totals.
class GroupCardLayout extends StatelessWidget {
  const GroupCardLayout({
    required this.itemCount,
    required this.itemBuilder,
    super.key,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 640 ? 2 : 1;
        const gap = CollectGroupCardTokens.gap;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var index = 0; index < itemCount; index++)
              SizedBox(width: width, child: itemBuilder(context, index)),
          ],
        );
      },
    );
  }
}

class _EditorialGroupCard extends StatelessWidget {
  const _EditorialGroupCard({
    required this.collection,
    required this.summary,
    required this.variant,
    this.onTap,
    this.primaryAction,
  });

  final CollectCollection collection;
  final CollectionSummary summary;
  final GroupCardVariant variant;
  final VoidCallback? onTap;
  final Widget? primaryAction;

  @override
  Widget build(BuildContext context) {
    final foreground = context.collectColors.onImagePrimary;
    final highContrast = MediaQuery.highContrastOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return RepaintBoundary(
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: CollectGroupCardTokens.radius,
              border: highContrast
                  ? Border.all(color: foreground, width: 2)
                  : null,
            ),
            child: ClipRRect(
              borderRadius: CollectGroupCardTokens.radius,
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: ColoredBox(color: CollectGroupCardTokens.footerInk),
                  ),
                  Positioned.fill(
                    child: ExcludeSemantics(
                      child: _GroupCoverMedia(collection: collection),
                    ),
                  ),
                  const Positioned.fill(child: _GroupCoverScrim()),
                  Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: CollectGroupCardTokens.radius,
                      focusColor: foreground.withValues(alpha: 0.22),
                      hoverColor: foreground.withValues(alpha: 0.10),
                      highlightColor: foreground.withValues(alpha: 0.12),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: width / CollectGroupCardTokens.aspectRatio,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: CollectGroupCardTokens.padding,
                              child: Row(
                                children: [
                                  ExcludeSemantics(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: foreground,
                                        shape: BoxShape.circle,
                                      ),
                                      child: SizedBox.square(
                                        dimension: 24,
                                        child: Icon(
                                          collectionTypeIcon(
                                            collection.collectionType,
                                          ),
                                          color:
                                              CollectGroupCardTokens.footerInk,
                                          size: 15,
                                        ),
                                      ),
                                    ),
                                  ),
                                  CollectSpacing.gapW8,
                                  Expanded(
                                    child: Text(
                                      collection.collectionType.label,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: foreground,
                                            fontSize: CollectGroupCardTokens
                                                .metadataSize,
                                            fontWeight: CollectTypography
                                                .weightSemibold,
                                          ),
                                    ),
                                  ),
                                  if (variant == GroupCardVariant.owned)
                                    _PrivacyGlyph(accent: foreground),
                                ],
                              ),
                            ),
                            SizedBox(height: width * 0.50),
                            _GroupEditorialDetails(
                              collection: collection,
                              summary: summary,
                              primaryAction: primaryAction,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Contribution stays a separate action from opening the group itself.
class GroupCardActionButton extends StatelessWidget {
  const GroupCardActionButton({
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = context.collectColors.onImagePrimary;
    return IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: foreground.withValues(alpha: 0.16),
        foregroundColor: foreground,
        side: BorderSide(color: foreground.withValues(alpha: 0.28)),
        fixedSize: const Size.square(CollectSpacing.iconTarget),
        minimumSize: const Size.square(CollectSpacing.iconTarget),
        padding: EdgeInsets.zero,
      ),
      icon: const Icon(CollectIcons.donate),
    );
  }
}
