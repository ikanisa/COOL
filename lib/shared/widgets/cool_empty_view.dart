import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/cool_foundations.dart';
import 'cool_button.dart';

/// Standardized empty-state view for screens and lists with no data.
class CoolEmptyView extends StatelessWidget {
  const CoolEmptyView({
    this.message,
    this.subtitle,
    this.title,
    this.icon = Icons.inbox_rounded,
    this.onAction,
    this.action,
    this.actionLabel,
    this.compact = false,
    this.isPremium = false,
    super.key,
  });

  final String? message;
  final String? subtitle;
  final String? title;
  final IconData icon;
  final VoidCallback? onAction;
  final VoidCallback? action;
  final String? actionLabel;
  final bool compact;
  final bool isPremium;

  String get _effectiveMessage => message ?? subtitle ?? '';
  VoidCallback? get _effectiveAction => onAction ?? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final iconSize = compact ? 32.0 : 44.0;
    final spacing = compact ? CoolSpace.x3 : CoolSpace.x6;

    return Semantics(
      container: true,
      label: '${title ?? ''} $_effectiveMessage',
      liveRegion: true,
      child: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: CoolSpace.x8,
              vertical: compact ? CoolSpace.x4 : CoolSpace.x10,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: iconSize + 28,
                    height: iconSize + 28,
                    decoration: BoxDecoration(
                      color: isPremium
                          ? colors.chipSelectedBackground
                          : colors.cardSurface,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.border),
                    ),
                    child: Icon(
                      icon,
                      size: iconSize,
                      color: isPremium ? colors.accent : colors.tertiaryText,
                    ),
                  ),
                ).animate().fadeIn(duration: 220.ms),
                SizedBox(height: spacing),
                if (title != null) ...[
                  Text(
                    title!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ).animate().fadeIn(delay: 60.ms, duration: 220.ms),
                  const SizedBox(height: CoolSpace.x2),
                ],
                Text(
                  _effectiveMessage,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colors.tertiaryText,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                  ),
                ).animate().fadeIn(delay: 120.ms, duration: 220.ms),
                if (_effectiveAction != null && actionLabel != null) ...[
                  SizedBox(height: spacing + 8),
                  SizedBox(
                    width: compact ? null : 200,
                    child: CoolButton(
                      label: actionLabel!,
                      onTap: _effectiveAction!,
                      variant: compact
                          ? CoolButtonVariant.secondary
                          : CoolButtonVariant.primary,
                    ),
                  ).animate().fadeIn(delay: 180.ms, duration: 220.ms),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
