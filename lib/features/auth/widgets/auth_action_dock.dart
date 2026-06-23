part of 'auth_screen_widgets.dart';

class AuthActionDock extends StatelessWidget {
  const AuthActionDock({
    required this.otpSent,
    required this.submitting,
    required this.resendRemaining,
    required this.onSubmit,
    required this.onAnotherNumber,
    required this.onResend,
    super.key,
  });

  final bool otpSent;
  final bool submitting;
  final int resendRemaining;
  final VoidCallback onSubmit;
  final VoidCallback? onAnotherNumber;
  final VoidCallback? onResend;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = colors.onImagePrimary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
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
              padding: const EdgeInsets.all(CollectSpacing.x4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CollectButton(
                    label: submitting
                        ? 'Checking'
                        : otpSent
                        ? 'Verify and continue'
                        : 'Send WhatsApp code',
                    icon: otpSent ? CollectIcons.shield : CollectIcons.sms,
                    onPressed: submitting ? null : onSubmit,
                    expand: true,
                  ),
                  if (otpSent) ...[
                    CollectSpacing.gap12,
                    Row(
                      children: [
                        Expanded(
                          child: CollectButton(
                            label: 'Change',
                            icon: CollectIcons.tune,
                            onPressed: onAnotherNumber,
                            variant: CollectButtonVariant.secondary,
                            expand: true,
                          ),
                        ),
                        CollectSpacing.gapW12,
                        Expanded(
                          child: CollectButton(
                            label: resendRemaining > 0
                                ? '${resendRemaining}s'
                                : 'Resend',
                            icon: CollectIcons.sync,
                            onPressed: onResend,
                            variant: CollectButtonVariant.secondary,
                            expand: true,
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
