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
    this.titleLabel,
    this.actions = const [],
    super.key,
  });

  final String? avatarLabel;
  final VoidCallback? onAvatarTap;
  final bool hasUnread;
  final String? titleLabel;
  final List<CollectTopChromeAction> actions;

  @override
  Widget build(BuildContext context) {
    final visibleActions = actions.take(2).toList();
    final label = titleLabel;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: SizedBox(
        height: 66,
        child: Row(
          children: [
            _TopChromeAvatar(
              label: avatarLabel,
              hasUnread: hasUnread,
              onTap: onAvatarTap,
            ),
            if (label != null && label.isNotEmpty) ...[
              CollectSpacing.gapW12,
              Expanded(child: _TopChromeTitlePill(label: label)),
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
    final foreground = CollectRuntimeTokens.chromeForeground(colors);
    final effectiveOnTap = onTap ?? () => context.go('/settings/profile');
    return Semantics(
      button: true,
      label: label == null ? 'Open profile' : 'Open profile for $label',
      hint: 'Opens the profile page',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: CollectRuntimeTokens.chromeAvatarGradient(),
              border: Border.all(
                color: CollectRuntimeTokens.chromeAvatarBorder(colors),
                width: 1.1,
              ),
              boxShadow: CollectRuntimeTokens.chromeAvatarShadow(),
            ),
            child: Material(
              color: colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () {
                  CollectHaptics.selection();
                  effectiveOnTap();
                },
                child: SizedBox.square(
                  dimension: 58,
                  child: Center(
                    child: SizedBox.square(
                      dimension: 30,
                      child: Image.asset(
                        CollectRuntimeAssets.officialLogo,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        excludeFromSemantics: true,
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
    );
  }
}

class _TopChromeTitlePill extends StatelessWidget {
  const _TopChromeTitlePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = CollectRuntimeTokens.chromeForeground(colors);
    return Semantics(
      label: label,
      child: Material(
        color: CollectRuntimeTokens.chromeControl(colors),
        borderRadius: CollectRadius.pillBorder,
        child: SizedBox(
          height: 58,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: CollectRadius.pillBorder,
              border: Border.all(
                color: CollectRuntimeTokens.chromeControlBorder(colors),
                width: 1.25,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CollectSpacing.x4,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: foreground,
                    fontWeight: CollectTypography.weightBold,
                    letterSpacing: CollectTypography.trackingDefault,
                  ),
                ),
              ),
            ),
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
    final foreground = CollectRuntimeTokens.chromeForeground(colors);
    return Semantics(
      button: true,
      label: action.tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: CollectRuntimeTokens.chromeControl(colors),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: action.onPressed == null
                  ? null
                  : () {
                      CollectHaptics.selection();
                      action.onPressed!();
                    },
              child: SizedBox.square(
                dimension: 58,
                child: Icon(action.icon, color: foreground, size: 30),
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
    this.foregroundColor,
    super.key,
  });

  final bool compact;
  final bool framed;
  final double? width;
  final double? height;
  final bool showWordmark;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final tokenBorder = CollectRuntimeTokens.inputBorder(colors);
    final baseWidth = compact ? 108.0 : 132.0;
    final baseHeight = compact ? 32.0 : 38.0;
    final wordmarkStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      color: foregroundColor ?? colors.textPrimary,
      fontWeight: CollectTypography.weightBold,
      letterSpacing: CollectTypography.trackingDefault,
    );
    final wordmarkPainter = TextPainter(
      text: TextSpan(
        text: CollectRuntimeAssets.brandLabel,
        style: wordmarkStyle,
      ),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final markHeight =
        height ?? math.max(baseHeight, wordmarkPainter.height.ceilToDouble());
    final iconWidth = (markHeight * 0.82).clamp(24, 32).toDouble();
    final adaptiveWidth = showWordmark
        ? iconWidth +
              CollectSpacing.x2 +
              wordmarkPainter.width.ceilToDouble() +
              CollectSpacing.x1
        : iconWidth;
    final markWidth = width ?? math.max(baseWidth, adaptiveWidth);
    wordmarkPainter.dispose();
    final mark = SizedBox(
      width: markWidth,
      height: markHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox.square(
            dimension: (markHeight * 0.82).clamp(24, 32).toDouble(),
            child: Image.asset(
              CollectRuntimeAssets.officialLogo,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              excludeFromSemantics: true,
            ),
          ),
          if (showWordmark) ...[
            CollectSpacing.gapW8,
            Flexible(
              child: Text(
                CollectRuntimeAssets.brandLabel,
                style: wordmarkStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
    return Semantics(
      label: 'Collect logo',
      image: true,
      child: ExcludeSemantics(
        child: framed
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: CollectRuntimeTokens.inputFill(colors),
                  borderRadius: BorderRadius.circular(markHeight * 0.5),
                  border: Border.all(color: tokenBorder),
                  boxShadow: CollectShadows.soft(),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: mark,
                ),
              )
            : SizedBox(width: markWidth, height: markHeight, child: mark),
      ),
    );
  }
}
