import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/cool_foundations.dart';
import '../../core/theme/app_theme_text.dart';

/// Button variants for the shared minimalist system.
enum CoolButtonVariant { primary, secondary, outline, ghost, accent, clay }

enum CoolButtonSize {
  sm,
  md,
  lg,
  icon;

  double get height => switch (this) {
    CoolButtonSize.sm => 36,
    CoolButtonSize.md => 44,
    CoolButtonSize.lg => 52,
    CoolButtonSize.icon => 40,
  };

  EdgeInsets get padding => switch (this) {
    CoolButtonSize.sm => const EdgeInsets.symmetric(horizontal: CoolSpace.x3),
    CoolButtonSize.md => const EdgeInsets.symmetric(horizontal: CoolSpace.x5),
    CoolButtonSize.lg => const EdgeInsets.symmetric(horizontal: CoolSpace.x6),
    CoolButtonSize.icon => EdgeInsets.zero,
  };

  double get fontSize => switch (this) {
    CoolButtonSize.sm => 14,
    CoolButtonSize.md => 14,
    CoolButtonSize.lg => 16,
    CoolButtonSize.icon => 0,
  };
}

/// A shared button with restrained emphasis and compact states.
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
    final radius = BorderRadius.circular(isIcon ? CoolRadii.md : CoolRadii.lg);

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
      borderRadius: BorderRadius.circular(CoolRadii.lg),
      child: Ink(
        decoration: decoration,
        child: InkWell(
          onTapDown: _enabled ? (_) => _scaleController.forward() : null,
          onTapUp: _enabled ? (_) => _scaleController.reverse() : null,
          onTapCancel: _enabled ? () => _scaleController.reverse() : null,
          onTap: _enabled ? _handleTap : null,
          borderRadius: BorderRadius.circular(CoolRadii.lg),
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
      fontWeight: FontWeight.w600,
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
      CoolButtonVariant.accent => Colors.white,
      CoolButtonVariant.clay => colors.accentForeground,
    };
  }

  Color? _resolvedBorder(CoolSemanticColors colors) {
    if (!_enabled) return colors.borderStrong.withValues(alpha: 0.15);
    return switch (widget.variant) {
      CoolButtonVariant.primary => null,
      CoolButtonVariant.secondary => colors.border,
      CoolButtonVariant.outline => colors.borderStrong,
      CoolButtonVariant.ghost => null,
      CoolButtonVariant.accent => null,
      CoolButtonVariant.clay => null,
    };
  }

  List<BoxShadow>? _resolvedShadow(CoolSemanticColors colors) {
    return switch (widget.variant) {
      CoolButtonVariant.primary => CoolShadows.primary(strength: 0.8),
      CoolButtonVariant.accent => CoolShadows.gold(strength: 0.7),
      CoolButtonVariant.clay => CoolShadows.clay(strength: 0.8),
      _ => null,
    };
  }

  Gradient? _resolvedGradient(CoolSemanticColors colors) {
    if (!_enabled) {
      return null;
    }
    return switch (widget.variant) {
      CoolButtonVariant.primary => null,
      CoolButtonVariant.secondary => null,
      CoolButtonVariant.accent => null,
      CoolButtonVariant.clay => null,
      _ => null,
    };
  }
}
