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
    final borderColor = foreground.withValues(alpha: 0.14);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              Material(
                color: CollectColors.transparentColor,
                child: InkWell(
                  key: const ValueKey('auth_country_code_picker'),
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(16),
                  ),
                  onTap: onCountryTap,
                  child: SizedBox(
                    height: 60,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16, right: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            countryCode,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: foreground,
                                  fontWeight: CollectTypography.weightSemibold,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            CollectIcons.chevronDown,
                            color: foreground.withValues(alpha: 0.58),
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Container(width: 1, height: 28, color: borderColor),
              Expanded(
                child: CollectAccessibleTextField(
                  controller: controller,
                  label: 'WhatsApp phone number',
                  onChanged: (_) => onChanged(),
                  builder: (focusNode) => TextField(
                    key: const ValueKey('auth_whatsapp_phone_input'),
                    focusNode: focusNode,
                    controller: controller,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]')),
                      LengthLimitingTextInputFormatter(15),
                    ],
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: foreground,
                      fontWeight: CollectTypography.weightSemibold,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      letterSpacing: CollectTypography.trackingDefault,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Phone number',
                      hintStyle: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(
                            color: foreground.withValues(alpha: 0.48),
                            fontWeight: CollectTypography.weightMedium,
                          ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 18,
                      ),
                    ),
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
