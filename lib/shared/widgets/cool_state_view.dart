import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
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
    IconData icon = Icons.inbox_rounded,
    String? actionLabel,
    VoidCallback? onAction,
    bool compact = false,
    Key? key,
  }) {
    return CoolStateView(
      key: key,
      tone: CoolStateTone.empty,
      title: title,
      message: message,
      icon: icon,
      actionLabel: actionLabel,
      onAction: onAction,
      compact: compact,
    );
  }

  factory CoolStateView.offline({
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    bool compact = false,
    Key? key,
  }) {
    return CoolStateView(
      key: key,
      tone: CoolStateTone.offline,
      title: title,
      message: message,
      icon: Icons.wifi_off_rounded,
      actionLabel: actionLabel,
      onAction: onAction,
      compact: compact,
    );
  }

  factory CoolStateView.error({
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    bool compact = false,
    Key? key,
  }) {
    return CoolStateView(
      key: key,
      tone: CoolStateTone.error,
      title: title,
      message: message,
      icon: Icons.error_outline_rounded,
      actionLabel: actionLabel,
      onAction: onAction,
      compact: compact,
    );
  }

  factory CoolStateView.success({
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    bool compact = false,
    Key? key,
  }) {
    return CoolStateView(
      key: key,
      tone: CoolStateTone.success,
      title: title,
      message: message,
      icon: Icons.check_circle_outline_rounded,
      actionLabel: actionLabel,
      onAction: onAction,
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

  Color get _accentColor => switch (tone) {
    CoolStateTone.loading => AppColors.accent,
    CoolStateTone.empty => AppColors.text3,
    CoolStateTone.offline => AppColors.orange,
    CoolStateTone.error => AppColors.red,
    CoolStateTone.success => AppColors.accent,
  };

  Color get _backgroundColor => switch (tone) {
    CoolStateTone.loading => AppColors.accentGlow,
    CoolStateTone.empty => AppColors.surface2,
    CoolStateTone.offline => AppColors.orange.withValues(alpha: 0.08),
    CoolStateTone.error => AppColors.red.withValues(alpha: 0.08),
    CoolStateTone.success => AppColors.accentGlow,
  };

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 18 : 20,
        vertical: compact ? 18 : 24,
      ),
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _accentColor.withValues(alpha: tone == CoolStateTone.empty ? 0.2 : 0.28),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 30 : 36, color: _accentColor),
          SizedBox(height: compact ? 10 : 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: compact ? 15 : 16,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
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
                variant: tone == CoolStateTone.error || tone == CoolStateTone.offline
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
