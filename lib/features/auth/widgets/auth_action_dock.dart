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
    return Padding(
      padding: embedded
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(
              CollectSpacing.x5,
              CollectSpacing.x2,
              CollectSpacing.x5,
              CollectSpacing.x4,
            ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            liveRegion: submitting,
            label: submitting
                ? otpSent
                      ? 'Verifying code'
                      : 'Sending WhatsApp code'
                : null,
            child: _AuthNativeActionButton(
              key: const ValueKey('auth_submit_button'),
              label: submitting
                  ? otpSent
                        ? 'Verifying code'
                        : 'Sending code'
                  : otpSent
                  ? 'Verify and continue'
                  : 'Send WhatsApp code',
              busy: submitting,
              onPressed: canSubmit ? onSubmit : null,
            ),
          ),
          if (otpSent) ...[
            CollectSpacing.gap8,
            Row(
              children: [
                Expanded(
                  child: _AuthNativeActionButton(
                    key: const ValueKey('auth_change_button'),
                    label: 'Change number',
                    onPressed: onAnotherNumber,
                    isPrimary: false,
                  ),
                ),
                Expanded(
                  child: _AuthNativeActionButton(
                    key: const ValueKey('auth_resend_button'),
                    label: resendRemaining > 0
                        ? '${resendRemaining}s'
                        : 'Resend',
                    onPressed: canResend ? onResend : null,
                    isPrimary: false,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AuthNativeActionButton extends StatelessWidget {
  const _AuthNativeActionButton({
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.isPrimary = true,
    super.key,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final enabled = onPressed != null;
    final foreground = isPrimary
        ? CollectColors.referenceChromeBlack.withValues(
            alpha: enabled ? 1 : 0.46,
          )
        : colors.onImagePrimary.withValues(alpha: enabled ? 0.92 : 0.38);
    final background = isPrimary
        ? enabled
              ? colors.onImagePrimary
              : colors.onImagePrimary.withValues(alpha: 0.46)
        : CollectColors.transparentColor;
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
              borderRadius: BorderRadius.circular(isPrimary ? 28 : 14),
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
            if (busy)
              SizedBox.square(
                dimension: isPrimary ? 19 : 17,
                child: CircularProgressIndicator(
                  key: const ValueKey('auth_submit_progress'),
                  strokeWidth: 2,
                  color: foreground,
                ),
              ),
            if (busy) CollectSpacing.gapW8,
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
