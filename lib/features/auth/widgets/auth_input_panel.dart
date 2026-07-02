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
    required this.countryFlag,
    required this.displayPhone,
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
  final String countryFlag;
  final String displayPhone;
  final VoidCallback onCountryTap;
  final VoidCallback onPhoneChanged;
  final VoidCallback onOtpChanged;
  final VoidCallback onCaptchaChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = colors.onImagePrimary;
    return ClipRRect(
      borderRadius: CollectRadius.cardLargeBorder,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: CollectColors.referenceChromeBlack.withValues(alpha: 0.22),
            borderRadius: CollectRadius.cardLargeBorder,
            border: Border.all(color: foreground.withValues(alpha: 0.12)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(CollectSpacing.x5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    otpSent
                        ? const Icon(
                            CollectIcons.shield,
                            color: CollectColors.brandMintGreen,
                            size: 22,
                          )
                        : const AuthWhatsAppMark(size: 24),
                    CollectSpacing.gapW8,
                    Expanded(
                      child: Text(
                        otpSent ? 'OTP' : 'WhatsApp',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                CollectSpacing.gap16,
                if (!otpSent)
                  AuthPhoneEntry(
                    controller: phoneController,
                    countryCode: countryCode,
                    countryFlag: countryFlag,
                    onCountryTap: onCountryTap,
                    onChanged: onPhoneChanged,
                  ),
                if (otpSent) ...[
                  AuthPhoneAnchor(
                    countryCode: countryCode,
                    countryFlag: countryFlag,
                    phone: displayPhone,
                  ),
                  CollectSpacing.gap16,
                  AuthOtpEntry(
                    controller: otpController,
                    onChanged: onOtpChanged,
                  ),
                  if (resendRemaining > 0) ...[
                    CollectSpacing.gap12,
                    Text(
                      'Resend in ${resendRemaining}s',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: foreground.withValues(alpha: 0.66),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
                if (env.authCaptchaEnabled) ...[
                  CollectSpacing.gap16,
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
                  CollectSpacing.gap16,
                  AuthStatusNotice(
                    title: 'Authentication failed',
                    message: error!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AuthPhoneEntry extends StatelessWidget {
  const AuthPhoneEntry({
    required this.controller,
    required this.countryCode,
    required this.countryFlag,
    required this.onCountryTap,
    required this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String countryCode;
  final String countryFlag;
  final VoidCallback onCountryTap;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = colors.onImagePrimary;
    final digits = controller.text.replaceAll(RegExp(r'\D'), '');
    final ready = digits.length >= 9 || controller.text.trim().startsWith('+');
    final screenWidth = MediaQuery.sizeOf(context).width;
    final selectorWidth = screenWidth < 360 ? 86.0 : 94.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: CollectColors.transparentColor,
          borderRadius: CollectRadius.mdBorder,
          child: InkWell(
            key: const ValueKey('auth_country_code_picker'),
            borderRadius: CollectRadius.mdBorder,
            onTap: onCountryTap,
            child: Ink(
              decoration: BoxDecoration(
                color: foreground.withValues(alpha: 0.10),
                borderRadius: CollectRadius.mdBorder,
                border: Border.all(color: foreground.withValues(alpha: 0.16)),
              ),
              child: SizedBox(
                height: 58,
                width: selectorWidth,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AuthCountryFlag(
                            countryCode: countryCode,
                            countryFlag: countryFlag,
                            size: 18,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            countryCode,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: foreground,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.visible,
                          ),
                          const SizedBox(width: 3),
                          Icon(
                            CollectIcons.chevronDown,
                            color: foreground.withValues(alpha: 0.72),
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
              color: foreground.withValues(alpha: 0.08),
              borderRadius: CollectRadius.mdBorder,
              border: Border.all(
                color: ready
                    ? CollectColors.brandMintGreen.withValues(alpha: 0.42)
                    : foreground.withValues(alpha: 0.14),
              ),
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
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
                letterSpacing: 0,
              ),
              decoration: InputDecoration(
                hintText: '788 123 456',
                hintStyle: TextStyle(color: foreground.withValues(alpha: 0.36)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
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

class AuthPhoneAnchor extends StatelessWidget {
  const AuthPhoneAnchor({
    required this.countryCode,
    required this.countryFlag,
    required this.phone,
    super.key,
  });

  final String countryCode;
  final String countryFlag;
  final String phone;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = colors.onImagePrimary;
    final raw = phone.trim();
    final display = raw.isEmpty ? countryCode : raw;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.08),
        borderRadius: CollectRadius.mdBorder,
        border: Border.all(color: foreground.withValues(alpha: 0.14)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 38,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: CollectColors.brandMintGreen.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: AuthCountryFlag(
                    countryCode: countryCode,
                    countryFlag: countryFlag,
                    size: 26,
                  ),
                ),
              ),
            ),
            CollectSpacing.gapW12,
            Expanded(
              child: Text(
                display,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthWhatsAppMark extends StatelessWidget {
  const AuthWhatsAppMark({this.size = 22, this.semanticLabel, super.key});

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final label = semanticLabel?.trim();
    final icon = SvgPicture.asset(
      'assets/runtime/collect_runtime/icons/whatsapp.svg',
      width: size,
      height: size,
      excludeFromSemantics: label == null || label.isEmpty,
      semanticsLabel: label == null || label.isEmpty ? null : label,
    );
    if (label == null || label.isEmpty) {
      return ExcludeSemantics(child: icon);
    }
    return Semantics(label: label, image: true, child: icon);
  }
}

class AuthCountryFlag extends StatelessWidget {
  const AuthCountryFlag({
    required this.countryCode,
    required this.countryFlag,
    this.size = 24,
    super.key,
  });

  final String countryCode;
  final String countryFlag;
  final double size;

  @override
  Widget build(BuildContext context) {
    final normalizedCode = countryCode.replaceAll(RegExp(r'\D'), '');
    if (normalizedCode == '250') {
      return Semantics(
        label: 'Rwanda',
        image: true,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.18),
          child: SvgPicture.asset(
            'assets/runtime/collect_runtime/icons/flag_rw.svg',
            width: size * 1.36,
            height: size,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    return SizedBox(
      width: size * 1.36,
      height: size,
      child: Center(
        child: Text(
          countryFlag,
          style: TextStyle(fontSize: size * 0.82, height: 1),
          textAlign: TextAlign.center,
          semanticsLabel: countryCode,
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.danger.withValues(alpha: 0.14),
        borderRadius: CollectRadius.mdBorder,
        border: Border.all(color: colors.danger.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(CollectSpacing.x4),
        child: Row(
          children: [
            Icon(CollectIcons.warning, color: colors.danger, size: 20),
            CollectSpacing.gapW12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colors.danger,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  CollectSpacing.gap4,
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onImagePrimary.withValues(alpha: 0.76),
                      fontWeight: FontWeight.w700,
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
