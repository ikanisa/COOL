part of 'auth_screen_widgets.dart';

class AuthInputPanel extends StatelessWidget {
  const AuthInputPanel({
    required this.otpSent,
    required this.phoneController,
    required this.otpController,
    required this.captchaController,
    required this.env,
    required this.error,
    required this.resendRemaining,
    required this.countryCode,
    required this.onCountryTap,
    required this.onPhoneChanged,
    required this.onOtpChanged,
    required this.onCaptchaChanged,
    super.key,
  });

  final bool otpSent;
  final TextEditingController phoneController;
  final TextEditingController otpController;
  final TextEditingController captchaController;
  final AppEnv env;
  final String? error;
  final int resendRemaining;
  final String countryCode;
  final VoidCallback onCountryTap;
  final VoidCallback onPhoneChanged;
  final VoidCallback onOtpChanged;
  final VoidCallback onCaptchaChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = colors.onImagePrimary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!otpSent)
          AuthPhoneEntry(
            controller: phoneController,
            countryCode: countryCode,
            onCountryTap: onCountryTap,
            onChanged: onPhoneChanged,
          ),
        if (otpSent) ...[
          AuthOtpEntry(controller: otpController, onChanged: onOtpChanged),
          CollectSpacing.gap20,
          Text(
            resendRemaining > 0
                ? 'Resend code in 00:${resendRemaining.toString().padLeft(2, '0')}'
                : "Didn't get the code? Use Resend or Change number below.",
            key: const ValueKey('auth_otp_recovery_message'),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: foreground.withValues(alpha: 0.90),
              fontWeight: CollectTypography.weightSemibold,
            ),
          ),
        ],
        if (env.authCaptchaEnabled) ...[
          CollectSpacing.gap20,
          CollectTextInput(
            controller: captchaController,
            label: env.authCaptchaProvider.isEmpty
                ? 'CAPTCHA'
                : env.authCaptchaProvider,
            textInputAction: TextInputAction.done,
            onChanged: (_) => onCaptchaChanged(),
          ),
        ],
        if (error != null) ...[
          CollectSpacing.gap20,
          AuthStatusNotice(title: 'Authentication failed', message: error!),
        ],
      ],
    );
  }
}

class AuthPhoneEntry extends StatelessWidget {
  const AuthPhoneEntry({
    required this.controller,
    required this.countryCode,
    required this.onCountryTap,
    required this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String countryCode;
  final VoidCallback onCountryTap;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = colors.onImagePrimary;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final selectorWidth = screenWidth < 360 ? 96.0 : 108.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: CollectColors.transparentColor,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            key: const ValueKey('auth_country_code_picker'),
            borderRadius: BorderRadius.circular(20),
            onTap: onCountryTap,
            child: Ink(
              decoration: BoxDecoration(
                color: foreground.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
              ),
              child: SizedBox(
                height: 66,
                width: selectorWidth,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CollectIcons.publicOutline,
                            color: foreground,
                            size: 20,
                            semanticLabel: 'Selected country',
                          ),
                          const SizedBox(width: 5),
                          Text(
                            countryCode,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: foreground,
                                  fontWeight: CollectTypography.weightBold,
                                  letterSpacing:
                                      CollectTypography.trackingDefault,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.visible,
                          ),
                          const SizedBox(width: 3),
                          Icon(
                            CollectIcons.chevronDown,
                            color: foreground.withValues(alpha: 0.82),
                            size: 14,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        CollectSpacing.gapW12,
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: foreground.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: TextField(
              key: const ValueKey('auth_whatsapp_phone_input'),
              controller: controller,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.telephoneNumber],
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]')),
                LengthLimitingTextInputFormatter(15),
              ],
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: foreground,
                fontWeight: CollectTypography.weightBold,
                fontFeatures: const [FontFeature.tabularFigures()],
                letterSpacing: CollectTypography.trackingDefault,
              ),
              decoration: InputDecoration(
                hintText: 'Enter your phone',
                hintStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: foreground.withValues(alpha: 0.36),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 19,
                ),
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
        ),
      ],
    );
  }
}

class AuthStatusNotice extends StatelessWidget {
  const AuthStatusNotice({
    required this.title,
    required this.message,
    super.key,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title. $message',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(CollectIcons.warning, color: colors.danger, size: 22),
            CollectSpacing.gapW12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colors.danger,
                      fontWeight: CollectTypography.weightBold,
                    ),
                  ),
                  CollectSpacing.gap4,
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onImagePrimary.withValues(alpha: 0.82),
                    ),
                    maxLines: 4,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
