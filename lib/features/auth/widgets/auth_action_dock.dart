part of 'auth_screen_widgets.dart';

class AuthActionDock extends StatelessWidget {
  const AuthActionDock({
    required this.otpSent,
    required this.submitting,
    required this.resendRemaining,
    required this.canSubmit,
    required this.canResend,
    required this.onSubmit,
    required this.onAnotherNumber,
    required this.onResend,
    this.embedded = false,
    super.key,
  });

  final bool otpSent;
  final bool submitting;
  final int resendRemaining;
  final bool canSubmit;
  final bool canResend;
  final VoidCallback? onSubmit;
  final VoidCallback? onAnotherNumber;
  final VoidCallback? onResend;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = colors.onImagePrimary;
    return Padding(
      padding: embedded
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(
              CollectSpacing.x4,
              CollectSpacing.x2,
              CollectSpacing.x4,
              CollectSpacing.x4,
            ),
      child: ClipRRect(
        borderRadius: CollectRadius.cardLargeBorder,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: CollectColors.referenceChromeBlack.withValues(alpha: 0.72),
              borderRadius: CollectRadius.cardLargeBorder,
              border: Border.all(color: foreground.withValues(alpha: 0.16)),
              boxShadow: [
                BoxShadow(
                  color: CollectColors.referenceChromeBlack.withValues(
                    alpha: 0.32,
                  ),
                  blurRadius: 34,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(CollectSpacing.x3),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _AuthNativeActionButton(
                    key: const ValueKey('auth_submit_button'),
                    label: submitting
                        ? 'Checking'
                        : otpSent
                        ? 'Verify and continue'
                        : 'Send WhatsApp code',
                    icon: otpSent ? CollectIcons.shield : null,
                    leading: otpSent ? null : const AuthSupportIcon(size: 20),
                    onPressed: canSubmit ? onSubmit : null,
                  ),
                  if (otpSent) ...[
                    CollectSpacing.gap12,
                    Row(
                      children: [
                        Expanded(
                          child: _AuthNativeActionButton(
                            key: const ValueKey('auth_change_button'),
                            label: 'Change',
                            icon: CollectIcons.tune,
                            onPressed: onAnotherNumber,
                            isPrimary: false,
                          ),
                        ),
                        CollectSpacing.gapW12,
                        Expanded(
                          child: _AuthNativeActionButton(
                            key: const ValueKey('auth_resend_button'),
                            label: resendRemaining > 0
                                ? '${resendRemaining}s'
                                : 'Resend',
                            icon: CollectIcons.sync,
                            onPressed: canResend ? onResend : null,
                            isPrimary: false,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthNativeActionButton extends StatelessWidget {
  const _AuthNativeActionButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.leading,
    this.isPrimary = true,
    super.key,
  });

  final String label;
  final IconData? icon;
  final Widget? leading;
  final VoidCallback? onPressed;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final enabled = onPressed != null;
    final foreground = isPrimary
        ? colors.onImagePrimary.withValues(alpha: enabled ? 1 : 0.42)
        : colors.onImagePrimary.withValues(alpha: enabled ? 0.92 : 0.38);
    final background = isPrimary
        ? enabled
              ? colors.actionColor
              : colors.onImagePrimary.withValues(alpha: 0.10)
        : colors.onImagePrimary.withValues(alpha: enabled ? 0.12 : 0.06);
    return SizedBox(
      width: double.infinity,
      height: isPrimary ? 56 : 48,
      child: TextButton(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(
            Size.fromHeight(isPrimary ? 56 : 48),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(isPrimary ? 16 : 14),
            ),
          ),
          backgroundColor: WidgetStatePropertyAll(background),
          foregroundColor: WidgetStatePropertyAll(foreground),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: CollectSpacing.x4),
          ),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null)
              IconTheme.merge(
                data: IconThemeData(
                  color: foreground,
                  size: isPrimary ? 19 : 17,
                ),
                child: leading!,
              )
            else if (icon != null)
              Icon(icon, color: foreground, size: isPrimary ? 19 : 17),
            CollectSpacing.gapW8,
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: foreground,
                  fontWeight: CollectTypography.weightBold,
                  letterSpacing: CollectTypography.trackingDefault,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
