import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/cool_foundations.dart';
import 'cool_button.dart';

/// Standardized error view used throughout the app.
class CoolErrorView extends StatelessWidget {
  const CoolErrorView({
    this.message,
    this.subtitle,
    this.onRetry,
    this.onAction,
    this.action,
    this.actionLabel,
    this.icon = Icons.error_outline_rounded,
    this.compact = false,
    super.key,
  });

  final String? message;
  final String? subtitle;
  final VoidCallback? onRetry;
  final VoidCallback? onAction;
  final VoidCallback? action;
  final String? actionLabel;
  final IconData icon;
  final bool compact;

  String get _effectiveMessage => message ?? subtitle ?? 'An error occurred';
  VoidCallback? get _effectiveAction => onRetry ?? onAction ?? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final iconSize = compact ? 36.0 : 52.0;
    final spacing = compact ? CoolSpace.x3 : CoolSpace.x5;

    return Semantics(
      label: 'Error: $_effectiveMessage',
      liveRegion: true,
      child: Center(
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
                      width: iconSize + 20,
                      height: iconSize + 20,
                      decoration: BoxDecoration(
                        color: colors.danger.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: iconSize, color: colors.danger),
                    ),
                  )
                  .animate()
                  .shake(duration: 500.ms, hz: 4)
                  .scale(begin: const Offset(0.8, 0.8), duration: 400.ms),
              SizedBox(height: spacing),
              Text(
                _effectiveMessage,
                textAlign: TextAlign.center,
                style:
                    (compact
                            ? theme.textTheme.bodySmall
                            : theme.textTheme.bodyMedium)
                        ?.copyWith(color: colors.secondaryText, height: 1.5),
              ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
              if (_effectiveAction != null) ...[
                SizedBox(height: spacing + 4),
                CoolButton(
                      label: actionLabel ?? 'Try Again',
                      onTap: _effectiveAction!,
                      variant: CoolButtonVariant.secondary,
                      fullWidth: false,
                    )
                    .animate()
                    .fadeIn(delay: 400.ms)
                    .scale(begin: const Offset(0.95, 0.95)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
