import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/cool_foundations.dart';
import '../../core/theme/app_theme_text.dart';

/// Button variants — Tactile Monolith system.
enum CoolButtonVariant {
  /// Partner Red background, white text, red glow shadow.
  primary,

  /// white/10 background, white text.
  secondary,

  /// Transparent background, white/10 border, white text.
  outline,

  /// Transparent, secondary text, no border.
  ghost,

  /// Gold background, black text, gold glow shadow.
  accent,

  /// Claymorphic Partner Red — dual inner-shadow 3D technique.
  /// Use for hero CTAs that need tactile emphasis.
  clay,
}

/// Button sizes — matches React UI kit.
enum CoolButtonSize {
  sm,
  md,
  lg,
  icon;

  double get height => switch (this) {
    CoolButtonSize.sm => 32,
    CoolButtonSize.md => 44,
    CoolButtonSize.lg => 56,
    CoolButtonSize.icon => 40,
  };

  EdgeInsets get padding => switch (this) {
    CoolButtonSize.sm => const EdgeInsets.symmetric(horizontal: CoolSpace.x3),
    CoolButtonSize.md => const EdgeInsets.symmetric(horizontal: CoolSpace.x6),
    CoolButtonSize.lg => const EdgeInsets.symmetric(horizontal: CoolSpace.x7),
    CoolButtonSize.icon => EdgeInsets.zero,
  };

  double get fontSize => switch (this) {
    CoolButtonSize.sm => 10,
    CoolButtonSize.md => 12,
    CoolButtonSize.lg => 14,
    CoolButtonSize.icon => 0,
  };
}

/// A styled button — Tactile Monolith system.
///
/// 6 variants, 4 sizes, press feedback (scale 0.95), JetBrains Mono uppercase.
class CoolButton extends StatefulWidget {
  const CoolButton({
    required this.label,
    this.onTap,
    this.variant = CoolButtonVariant.primary,
    this.size = CoolButtonSize.md,
    this.isLoading = false,
    this.isDisabled = false,
    this.fullWidth = true,
    this.icon,
    this.semanticsLabel,
    super.key,
  });

  final String label;
  final VoidCallback? onTap;
  final CoolButtonVariant variant;
  final CoolButtonSize size;
  final bool isLoading;
  final bool isDisabled;
  final bool fullWidth;
  final IconData? icon;
  final String? semanticsLabel;

  @override
  State<CoolButton> createState() => _CoolButtonState();
}

class _CoolButtonState extends State<CoolButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: CoolMotion.press,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  bool get _enabled =>
      widget.onTap != null && !widget.isLoading && !widget.isDisabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final isIcon = widget.size == CoolButtonSize.icon;
    final radius = BorderRadius.circular(
      isIcon ? CoolRadii.md : CoolRadii.pill,
    );

    final bg = _resolvedBg(colors);
    final fg = _resolvedFg(colors);
    final border = _resolvedBorder(colors);
    final shadow = _resolvedShadow(colors);
    final gradient = _resolvedGradient(colors);

    final decoration = BoxDecoration(
      color: gradient == null ? bg : null,
      gradient: gradient,
      borderRadius: radius,
      border: border != null ? Border.all(color: border, width: 1) : null,
      boxShadow: _enabled ? shadow : null,
    );

    return MouseRegion(
      cursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Semantics(
          label: widget.semanticsLabel ?? widget.label,
          button: true,
          enabled: _enabled,
          onTap: _enabled ? _handleTap : null,
          excludeSemantics: true,
          child: SizedBox(
            width: widget.fullWidth && !isIcon ? double.infinity : null,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: widget.size.height),
              child: isIcon
                  ? SizedBox(
                      width: widget.size.height,
                      height: widget.size.height,
                      child: _buildIconButton(colors, fg, decoration),
                    )
                  : _buildButton(colors, fg, decoration),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildButton(
    CoolSemanticColors colors,
    Color fg,
    BoxDecoration decoration,
  ) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(CoolRadii.pill),
      child: Ink(
        decoration: decoration,
        child: InkWell(
          onTapDown: _enabled ? (_) => _scaleController.forward() : null,
          onTapUp: _enabled ? (_) => _scaleController.reverse() : null,
          onTapCancel: _enabled ? () => _scaleController.reverse() : null,
          onTap: _enabled ? _handleTap : null,
          borderRadius: BorderRadius.circular(CoolRadii.pill),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Padding(padding: widget.size.padding, child: _buildChild(fg)),
        ),
      ),
    );
  }

  Widget _buildIconButton(
    CoolSemanticColors colors,
    Color fg,
    BoxDecoration decoration,
  ) {
    return GestureDetector(
      onTapDown: _enabled ? (_) => _scaleController.forward() : null,
      onTapUp: _enabled ? (_) => _scaleController.reverse() : null,
      onTapCancel: _enabled ? () => _scaleController.reverse() : null,
      onTap: _enabled ? _handleTap : null,
      child: Container(
        width: widget.size.height,
        height: widget.size.height,
        decoration: decoration,
        child: Icon(widget.icon, size: 18, color: fg),
      ),
    );
  }

  Widget _buildChild(Color fg) {
    if (widget.isLoading) {
      return Center(
        child: CupertinoActivityIndicator(
          key: const ValueKey('cool_button_loading'),
          radius: 10,
          color: fg,
        ),
      );
    }

    final textStyle = TextStyle(
      fontFamily: AppThemeText.labelFontFamily,
      color: fg,
      fontSize: widget.size.fontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
    );

    final textWidget = Text(
      widget.label,
      softWrap: true,
      textAlign: TextAlign.center,
      style: textStyle,
    );

    if (widget.icon == null) {
      return Center(child: textWidget);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(widget.icon, size: 16, color: fg),
        const SizedBox(width: CoolSpace.x2),
        Flexible(child: textWidget),
      ],
    );
  }

  void _handleTap() {
    final isHero =
        widget.variant == CoolButtonVariant.primary ||
        widget.variant == CoolButtonVariant.accent ||
        widget.variant == CoolButtonVariant.clay;
    if (isHero) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    widget.onTap?.call();
  }

  Color _resolvedBg(CoolSemanticColors colors) {
    if (!_enabled) return colors.cardSurfaceStrong;
    return switch (widget.variant) {
      CoolButtonVariant.primary => colors.buttonPrimaryBackground,
      CoolButtonVariant.secondary => colors.buttonSecondaryBackground,
      CoolButtonVariant.outline => Colors.transparent,
      CoolButtonVariant.ghost => Colors.transparent,
      CoolButtonVariant.accent => colors.accentGold,
      CoolButtonVariant.clay => colors.buttonPrimaryBackground,
    };
  }

  Color _resolvedFg(CoolSemanticColors colors) {
    if (!_enabled) return colors.tertiaryText;
    return switch (widget.variant) {
      CoolButtonVariant.primary => colors.accentForeground,
      CoolButtonVariant.secondary => colors.primaryText,
      CoolButtonVariant.outline => colors.primaryText,
      CoolButtonVariant.ghost => colors.secondaryText,
      CoolButtonVariant.accent => Colors.black,
      CoolButtonVariant.clay => colors.accentForeground,
    };
  }

  Color? _resolvedBorder(CoolSemanticColors colors) {
    if (!_enabled) return colors.borderStrong.withValues(alpha: 0.15);
    return switch (widget.variant) {
      CoolButtonVariant.primary => null,
      CoolButtonVariant.secondary => null,
      CoolButtonVariant.outline => colors.borderStrong.withValues(alpha: 0.15),
      CoolButtonVariant.ghost => null,
      CoolButtonVariant.accent => null,
      CoolButtonVariant.clay => null,
    };
  }

  List<BoxShadow>? _resolvedShadow(CoolSemanticColors colors) {
    return switch (widget.variant) {
      CoolButtonVariant.primary => CoolShadows.primary(),
      CoolButtonVariant.accent => CoolShadows.gold(),
      CoolButtonVariant.clay => CoolShadows.clay(),
      _ => null,
    };
  }

  Gradient? _resolvedGradient(CoolSemanticColors colors) {
    if (!_enabled) {
      return null;
    }
    return switch (widget.variant) {
      CoolButtonVariant.primary => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          colors.accentStrong.withValues(alpha: 0.92),
          colors.buttonPrimaryBackground,
        ],
      ),
      CoolButtonVariant.secondary => null,
      CoolButtonVariant.accent => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          colors.accentGold,
          colors.accentGold.withValues(alpha: 0.82),
        ],
      ),
      CoolButtonVariant.clay => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[colors.accentStrong, colors.accent, colors.accentDeep],
      ),
      _ => null,
    };
  }
}
