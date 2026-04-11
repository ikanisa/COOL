import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

/// A collapsible section with a compact header and smooth expand/collapse.
///
/// Use for hiding secondary information (descriptions, optional settings,
/// detailed stats) behind a single-tap interaction.
///
/// ```dart
/// CoolExpandableSection(
///   header: 'Description',
///   initiallyExpanded: false,
///   child: Text(group.description),
/// )
/// ```
class CoolExpandableSection extends StatefulWidget {
  const CoolExpandableSection({
    required this.header,
    required this.child,
    this.initiallyExpanded = false,
    this.headerStyle,
    this.trailing,
    super.key,
  });

  /// Section header text.
  final String header;

  /// Content shown when expanded.
  final Widget child;

  /// Whether the section starts expanded.
  final bool initiallyExpanded;

  /// Override header text style.
  final TextStyle? headerStyle;

  /// Optional trailing widget in the header row (besides the expand icon).
  final Widget? trailing;

  @override
  State<CoolExpandableSection> createState() => _CoolExpandableSectionState();
}

class _CoolExpandableSectionState extends State<CoolExpandableSection>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _heightFactor;
  late Animation<double> _iconTurns;
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _controller = AnimationController(
      vsync: this,
      duration: CoolMotion.standard,
    );
    _heightFactor = _controller.drive(CurveTween(curve: CoolMotion.enterCurve));
    _iconTurns = _controller.drive(
      Tween<double>(begin: 0.0, end: 0.5)
          .chain(CurveTween(curve: CoolMotion.enterCurve)),
    );

    if (_isExpanded) {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    // Respect reduced motion preference.
    final duration = CoolMotion.resolve(context, CoolMotion.standard);
    if (_controller.duration != duration) {
      _controller.duration = duration;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header row — always visible.
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(CoolRadii.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: CoolSpace.x3,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.header,
                      style: widget.headerStyle ??
                          text.headline(
                            theme.textTheme.titleSmall,
                            fontWeight: FontWeight.w600,
                            color: colors.primaryText,
                          ),
                    ),
                  ),
                  if (widget.trailing != null) ...[
                    const SizedBox(width: CoolSpace.x2),
                    widget.trailing!,
                  ],
                  const SizedBox(width: CoolSpace.x2),
                  RotationTransition(
                    turns: _iconTurns,
                    child: Icon(
                      CoolIcons.expand,
                      size: 20,
                      color: colors.tertiaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Collapsible content.
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return ClipRect(
              child: Align(
                alignment: Alignment.topLeft,
                heightFactor: _heightFactor.value,
                child: child,
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.only(bottom: CoolSpace.x2),
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
