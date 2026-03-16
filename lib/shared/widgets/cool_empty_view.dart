import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/cool_palette.dart';
import 'cool_button.dart';

/// Standardized empty-state view for screens and lists with no data.
///
/// Displays a centered icon and message. Optionally includes an action
/// button for the user to take next steps (e.g. "Create your first trip").
class CoolEmptyView extends StatelessWidget {
  const CoolEmptyView({
    required this.subtitle,
    this.title,
    this.icon = Icons.inbox_rounded,
    this.onAction,
    this.actionLabel,
    this.compact = false,
    this.isPremium = false,
    super.key,
  });

  /// User-facing empty-state subtitle message.
  final String subtitle;

  /// Optional bold title for the empty state.
  final String? title;

  /// Icon displayed above the message.
  final IconData icon;

  /// Optional callback for the action button.
  final VoidCallback? onAction;

  /// Label for the action button. Required if [onAction] is provided.
  final String? actionLabel;

  /// If true, renders in a more compact layout.
  final bool compact;

  /// If true, applies 'Soft Liquid Glass' premium styling to the icon container.
  final bool isPremium;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final iconSize = compact ? 32.0 : 44.0;
    final spacing = compact ? 12.0 : 24.0;

    return Semantics(
      container: true,
      label: '${title ?? ''} $subtitle',
      liveRegion: true,
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 32,
            vertical: compact ? 16 : 64,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Container(
                  width: iconSize + 32,
                  height: iconSize + 32,
                  decoration: isPremium
                      ? BoxDecoration(
                          gradient: AppColors.cardGradient,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.rsBlue.withAlpha(50), 
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.rsBlueGlow,
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        )
                      : BoxDecoration(
                          color: palette.surface2,
                          shape: BoxShape.circle,
                          border: Border.all(color: palette.border, width: 1.5),
                        ),
                  child: Icon(icon, size: iconSize, color: isPremium ? AppColors.rsWhite : palette.text3),
                ),
              ),
              SizedBox(height: spacing),
              if (title != null) ...[
                Text(
                  title!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: palette.text3,
                      fontWeight: FontWeight.w500,
                      height: 1.6,
                    ),
              ),
              if (onAction != null && actionLabel != null) ...[
                SizedBox(height: spacing + 8),
                SizedBox(
                  width: compact ? null : 200,
                  child: CoolButton(
                    label: actionLabel!,
                    onTap: onAction!,
                    variant: compact
                        ? CoolButtonVariant.secondary
                        : CoolButtonVariant.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
