import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/env/app_env.dart';
import '../../../shared/widgets/collect_components.dart';

class AuthBrandHeader extends StatelessWidget {
  const AuthBrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [CollectBrandMark(framed: false, compact: true)],
    );
  }
}

class AuthHeadline extends StatelessWidget {
  const AuthHeadline({required this.otpSent, required this.phone, super.key});

  final bool otpSent;
  final String phone;

  @override
  Widget build(BuildContext context) {
    final foreground = context.collectColors.onImagePrimary;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          otpSent ? 'Verify WhatsApp' : 'Sign in',
          style: textTheme.displaySmall?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w900,
            height: 0.98,
            letterSpacing: 0,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        CollectSpacing.gap8,
        Text(
          otpSent ? 'Code sent to $phone' : 'Use your WhatsApp number.',
          style: textTheme.titleMedium?.copyWith(
            color: foreground.withValues(alpha: 0.70),
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

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
                    Icon(
                      otpSent ? CollectIcons.shield : CollectIcons.sms,
                      color: CollectColors.brandMintGreen,
                      size: 22,
                    ),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.transparent,
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
                width: 126,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      countryFlag,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        countryCode,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      CollectIcons.chevronDown,
                      color: foreground.withValues(alpha: 0.72),
                      size: 18,
                    ),
                  ],
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
                  child: Text(
                    countryFlag,
                    style: Theme.of(context).textTheme.titleMedium,
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

class AuthOtpEntry extends StatefulWidget {
  const AuthOtpEntry({
    required this.controller,
    required this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  State<AuthOtpEntry> createState() => AuthOtpEntryState();
}

class AuthOtpEntryState extends State<AuthOtpEntry> {
  static const _digitCount = 6;

  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _nodes;
  var _syncing = false;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(_digitCount, (_) => TextEditingController());
    _nodes = List.generate(_digitCount, (_) => FocusNode());
    widget.controller.addListener(_syncFromExternal);
    _syncFromExternal();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromExternal);
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncFromExternal() {
    if (_syncing) return;
    final digits = widget.controller.text.replaceAll(RegExp(r'\D'), '');
    for (var index = 0; index < _digitCount; index += 1) {
      final value = index < digits.length ? digits[index] : '';
      if (_controllers[index].text != value) {
        _controllers[index].text = value;
      }
    }
  }

  void _publish() {
    final value = _controllers.map((controller) => controller.text).join();
    _syncing = true;
    widget.controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _syncing = false;
    widget.onChanged();
  }

  void _handleDigit(int index, String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 1) {
      for (var offset = 0; offset < digits.length; offset += 1) {
        final target = index + offset;
        if (target >= _digitCount) break;
        _controllers[target].text = digits[offset];
      }
      final nextIndex = (index + digits.length)
          .clamp(0, _digitCount - 1)
          .toInt();
      _nodes[nextIndex].requestFocus();
      _publish();
      return;
    }
    final digit = digits;
    if (_controllers[index].text != digit) {
      _controllers[index].text = digit;
    }
    if (digit.isNotEmpty && index < _digitCount - 1) {
      _nodes[index + 1].requestFocus();
    }
    _publish();
  }

  KeyEventResult _handleKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.backspace ||
        _controllers[index].text.isNotEmpty ||
        index == 0) {
      return KeyEventResult.ignored;
    }
    _controllers[index - 1].clear();
    _nodes[index - 1].requestFocus();
    _publish();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final foreground = context.collectColors.onImagePrimary;
    return Semantics(
      textField: true,
      label: 'Verification code',
      child: Row(
        children: List.generate(_digitCount, (index) {
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: index == _digitCount - 1 ? 0 : 6),
              child: Focus(
                onKeyEvent: (_, event) => _handleKey(index, event),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: foreground.withValues(alpha: 0.08),
                    borderRadius: CollectRadius.mdBorder,
                    border: Border.all(
                      color: foreground.withValues(alpha: 0.16),
                    ),
                  ),
                  child: SizedBox(
                    height: 58,
                    child: TextField(
                      key: ValueKey('auth_otp_digit_$index'),
                      controller: _controllers[index],
                      focusNode: _nodes[index],
                      keyboardType: TextInputType.number,
                      textInputAction: index == _digitCount - 1
                          ? TextInputAction.done
                          : TextInputAction.next,
                      textAlign: TextAlign.center,
                      textAlignVertical: TextAlignVertical.center,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w900,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        letterSpacing: 0,
                      ),
                      decoration: const InputDecoration(
                        counterText: '',
                        border: InputBorder.none,
                      ),
                      onChanged: (value) => _handleDigit(index, value),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
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
