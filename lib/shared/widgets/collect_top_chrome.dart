part of 'collect_chrome.dart';

class CollectTopChromeAction {
  const CollectTopChromeAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.hasBadge = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool hasBadge;
}

class CollectTopChrome extends StatelessWidget {
  const CollectTopChrome({
    this.avatarLabel,
    this.onAvatarTap,
    this.hasUnread = false,
    this.searchLabel = 'Search',
    this.searchController,
    this.onSearchChanged,
    this.onSearchTap,
    this.actions = const [],
    this.showSearch = true,
    super.key,
  });

  final String? avatarLabel;
  final VoidCallback? onAvatarTap;
  final bool hasUnread;
  final String searchLabel;
  final TextEditingController? searchController;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onSearchTap;
  final List<CollectTopChromeAction> actions;
  final bool showSearch;

  @override
  Widget build(BuildContext context) {
    final visibleActions = actions.take(2).toList();
    return Semantics(
      container: true,
      label: 'Primary screen actions',
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            _TopChromeAvatar(
              label: avatarLabel,
              hasUnread: hasUnread,
              onTap: onAvatarTap,
            ),
            if (showSearch) ...[
              CollectSpacing.gapW12,
              Expanded(
                child: searchController == null
                    ? _TopChromeSearchButton(
                        label: searchLabel,
                        onTap: onSearchTap,
                      )
                    : _TopChromeSearchField(
                        controller: searchController!,
                        label: searchLabel,
                        onChanged: onSearchChanged,
                      ),
              ),
            ] else
              const Spacer(),
            if (visibleActions.isNotEmpty) CollectSpacing.gapW12,
            for (var index = 0; index < visibleActions.length; index += 1) ...[
              if (index > 0) CollectSpacing.gapW8,
              _TopChromeActionButton(action: visibleActions[index]),
            ],
          ],
        ),
      ),
    );
  }
}

class _TopChromeAvatar extends StatelessWidget {
  const _TopChromeAvatar({
    required this.label,
    required this.hasUnread,
    this.onTap,
  });

  final String? label;
  final bool hasUnread;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = colors.onImagePrimary;
    final effectiveOnTap = onTap ?? () => context.go('/settings/profile');
    return Tooltip(
      message: 'Open profile',
      child: Semantics(
        button: true,
        label: label == null ? 'Open profile' : 'Open profile for $label',
        hint: 'Opens the profile page',
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    CollectColors.referencePaymentsPurple.withValues(
                      alpha: 0.96,
                    ),
                    CollectColors.inkPrimary.withValues(alpha: 0.96),
                  ],
                ),
                border: Border.all(
                  color: foreground.withValues(alpha: 0.22),
                  width: 1.1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: CollectColors.inkPrimary.withValues(alpha: 0.24),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Material(
                color: colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: effectiveOnTap,
                  child: SizedBox.square(
                    dimension: 52,
                    child: Center(
                      child: ClipOval(
                        child: Image.asset(
                          CollectBrandMark.appIconAssetPath,
                          width: 38,
                          height: 38,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            CollectIcons.people,
                            color: foreground,
                            size: 30,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (hasUnread)
              Positioned(
                right: 2,
                top: 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.brandAction,
                    shape: BoxShape.circle,
                    border: Border.all(color: foreground, width: 2),
                  ),
                  child: const SizedBox.square(dimension: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TopChromeSearchButton extends StatelessWidget {
  const _TopChromeSearchButton({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = context.collectColors.onImagePrimary;
    return Tooltip(
      message: label,
      child: Material(
        color: CollectColors.inkPrimary.withValues(alpha: 0.92),
        borderRadius: CollectRadius.pillBorder,
        child: InkWell(
          borderRadius: CollectRadius.pillBorder,
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: CollectRadius.pillBorder,
              border: Border.all(color: foreground.withValues(alpha: 0.24)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CollectSpacing.x4,
              ),
              child: Row(
                children: [
                  Icon(CollectIcons.search, color: foreground),
                  CollectSpacing.gapW12,
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopChromeSearchField extends StatelessWidget {
  const _TopChromeSearchField({
    required this.controller,
    required this.label,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final foreground = context.collectColors.onImagePrimary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CollectColors.inkPrimary.withValues(alpha: 0.92),
        borderRadius: CollectRadius.pillBorder,
        border: Border.all(color: foreground.withValues(alpha: 0.24)),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        minLines: 1,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w800,
        ),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: label,
          hintStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: foreground.withValues(alpha: 0.76),
            fontWeight: FontWeight.w800,
          ),
          prefixIcon: Icon(CollectIcons.search, color: foreground),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: Icon(Icons.close_rounded, color: foreground),
                  onPressed: () {
                    controller.clear();
                    onChanged?.call('');
                  },
                ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: CollectSpacing.x3,
            vertical: CollectSpacing.x3,
          ),
        ),
      ),
    );
  }
}

class _TopChromeActionButton extends StatelessWidget {
  const _TopChromeActionButton({required this.action});

  final CollectTopChromeAction action;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = colors.onImagePrimary;
    return Tooltip(
      message: action.tooltip,
      child: Semantics(
        button: true,
        label: action.tooltip,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: CollectColors.inkPrimary.withValues(alpha: 0.92),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: action.onPressed,
                child: SizedBox.square(
                  dimension: 52,
                  child: Icon(action.icon, color: foreground, size: 26),
                ),
              ),
            ),
            if (action.hasBadge)
              Positioned(
                right: 4,
                top: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.brandAction,
                    shape: BoxShape.circle,
                    border: Border.all(color: foreground, width: 2),
                  ),
                  child: const SizedBox.square(dimension: 10),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class CollectBrandMark extends StatelessWidget {
  const CollectBrandMark({
    this.compact = false,
    this.framed = true,
    this.width,
    this.height,
    this.showWordmark = true,
    super.key,
  });

  static const assetPath =
      'assets/brand/generated/collect_wordmark_transparent.png';
  static const appIconAssetPath = 'assets/brand/collect_app_icon_static.png';

  final bool compact;
  final bool framed;
  final double? width;
  final double? height;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final markWidth = width ?? (compact ? 108.0 : 132.0);
    final markHeight = height ?? (compact ? 32.0 : 38.0);
    final wordmark = Image.asset(
      assetPath,
      width: markWidth,
      height: markHeight,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
    );
    return Semantics(
      label: 'Collect logo',
      image: true,
      child: ExcludeSemantics(
        child: framed
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.glassControl,
                  borderRadius: BorderRadius.circular(markHeight * 0.5),
                  border: Border.all(color: colors.glassBorder),
                  boxShadow: CollectShadows.soft(),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(markHeight * 0.46),
                  child: wordmark,
                ),
              )
            : SizedBox(
                width: markWidth,
                height: markHeight,
                child: FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                  child: wordmark,
                ),
              ),
      ),
    );
  }
}
