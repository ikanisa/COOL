import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';
import 'cool_button.dart';

enum CoolStateTone { loading, empty, offline, error, success }

class CoolStateView extends StatelessWidget {
  const CoolStateView({
    required this.tone,
    required this.title,
    required this.message,
    required this.icon,
    this.actionLabel,
    this.onAction,
    this.compact = false,
    this.center = true,
    super.key,
  });

  factory CoolStateView.loading({
    String title = 'Loading',
    String message = 'Please wait while this section loads.',
    bool compact = false,
    Key? key,
  }) {
    return CoolStateView(
      key: key,
      tone: CoolStateTone.loading,
      title: title,
      message: message,
      icon: Icons.hourglass_top_rounded,
      compact: compact,
    );
  }

  factory CoolStateView.empty({
    required String title,
    required String message,
    String? subtitle,
    IconData icon = Icons.inbox_rounded,
    String? actionLabel,
    VoidCallback? onAction,
    VoidCallback? action,
    bool compact = false,
    Key? key,
  }) {
    return CoolStateView(
      key: key,
      tone: CoolStateTone.empty,
      title: title,
      message: subtitle ?? message,
      icon: icon,
      actionLabel: actionLabel,
      onAction: onAction ?? action,
      compact: compact,
    );
  }

  factory CoolStateView.offline({
    required String title,
    required String message,
    String? subtitle,
    String? actionLabel,
    VoidCallback? onAction,
    VoidCallback? action,
    bool compact = false,
    Key? key,
  }) {
    return CoolStateView(
      key: key,
      tone: CoolStateTone.offline,
      title: title,
      message: subtitle ?? message,
      icon: Icons.wifi_off_rounded,
      actionLabel: actionLabel,
      onAction: onAction ?? action,
      compact: compact,
    );
  }

  factory CoolStateView.error({
    required String title,
    required String message,
    String? subtitle,
    String? actionLabel,
    VoidCallback? onAction,
    VoidCallback? action,
    bool compact = false,
    Key? key,
  }) {
    return CoolStateView(
      key: key,
      tone: CoolStateTone.error,
      title: title,
      message: subtitle ?? message,
      icon: Icons.error_outline_rounded,
      actionLabel: actionLabel,
      onAction: onAction ?? action,
      compact: compact,
    );
  }

  factory CoolStateView.success({
    required String title,
    required String message,
    String? subtitle,
    String? actionLabel,
    VoidCallback? onAction,
    VoidCallback? action,
    bool compact = false,
    Key? key,
  }) {
    return CoolStateView(
      key: key,
      tone: CoolStateTone.success,
      title: title,
      message: subtitle ?? message,
      icon: Icons.check_circle_outline_rounded,
      actionLabel: actionLabel,
      onAction: onAction ?? action,
      compact: compact,
    );
  }

  final CoolStateTone tone;
  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;
  final bool center;

  Color _accentColor(CoolSemanticColors colors) => switch (tone) {
    CoolStateTone.loading => colors.accent,
    CoolStateTone.empty => colors.tertiaryText,
    CoolStateTone.offline => colors.warning,
    CoolStateTone.error => colors.danger,
    CoolStateTone.success => colors.accent,
  };

  Color _backgroundColor(CoolSemanticColors colors) => switch (tone) {
    CoolStateTone.loading => colors.accent.withValues(alpha: 0.08),
    CoolStateTone.empty => colors.cardSurface,
    CoolStateTone.offline => colors.warning.withValues(alpha: 0.08),
    CoolStateTone.error => colors.danger.withValues(alpha: 0.08),
    CoolStateTone.success => colors.accent.withValues(alpha: 0.08),
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final accentColor = _accentColor(colors);
    final content = Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? CoolSpace.x4 : CoolSpace.x5,
        vertical: compact ? CoolSpace.x4 : CoolSpace.x6,
      ),
      decoration: BoxDecoration(
        color: _backgroundColor(colors),
        borderRadius: BorderRadius.circular(CoolRadii.md),
        border: Border.all(
          color: accentColor.withValues(
            alpha: tone == CoolStateTone.empty ? 0.2 : 0.28,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 30 : 36, color: accentColor),
          SizedBox(height: compact ? 10 : 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style:
                (compact
                        ? theme.textTheme.titleSmall
                        : theme.textTheme.titleMedium)
                    ?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.primaryText,
                    ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            message,
            textAlign: TextAlign.center,
            style:
                (compact
                        ? theme.textTheme.bodySmall
                        : theme.textTheme.bodyMedium)
                    ?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colors.secondaryText,
                      height: 1.45,
                    ),
          ),
          if (actionLabel != null && onAction != null) ...[
            SizedBox(height: compact ? 14 : 16),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: CoolButton(
                label: actionLabel!,
                onTap: onAction!,
                variant:
                    tone == CoolStateTone.error || tone == CoolStateTone.offline
                    ? CoolButtonVariant.secondary
                    : CoolButtonVariant.primary,
                fullWidth: false,
              ),
            ),
          ],
        ],
      ),
    );

    return Semantics(
      label: '$title. $message',
      liveRegion: tone == CoolStateTone.error || tone == CoolStateTone.offline,
      child: center
          ? Center(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 0 : 4,
                  vertical: compact ? 0 : 12,
                ),
                child: content,
              ),
            )
          : content,
    );
  }
}
