import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_market.dart';
import '../../../core/config/country_catalog.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/phone_validator.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../providers/auth_provider.dart';
import '../providers/whatsapp_otp_provider.dart';

/// Full-screen WhatsApp OTP verification.
///
/// Returns `true` when the user successfully verifies and logs in.
/// Returns `false` or `null` when the user dismisses.
class WhatsAppOtpScreen extends ConsumerStatefulWidget {
  const WhatsAppOtpScreen({super.key, this.initialPhone});

  final String? initialPhone;

  /// Show as a full-screen route pushed on top of current navigator.
  static Future<bool?> show(BuildContext context, {String? initialPhone}) {
    return Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => WhatsAppOtpScreen(initialPhone: initialPhone),
      ),
    );
  }

  @override
  ConsumerState<WhatsAppOtpScreen> createState() => _WhatsAppOtpScreenState();
}

class _WhatsAppOtpScreenState extends ConsumerState<WhatsAppOtpScreen> {
  final _phoneController = TextEditingController();
  final _otpControllers = List.generate(6, (_) => TextEditingController());
  final _otpFocusNodes = List.generate(6, (_) => FocusNode());
  bool _isVerifyingCode = false;
  Timer? _retryTimer;
  int _retryCountdown = 0;

  @override
  void initState() {
    super.initState();
    // Reset OTP state on open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.read(whatsAppOtpStateProvider.notifier).reset();
      final initialPhone = _normalizeInitialPhone(widget.initialPhone);
      if (initialPhone.isNotEmpty) {
        _phoneController.text = initialPhone;
      }
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _phoneController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  CoolCountry get _country =>
      CoolCountryCatalog.resolve(country: AppMarket.countryCode);

  String _normalizeInitialPhone(String? phone) {
    final trimmed = phone?.trim() ?? '';
    if (trimmed.isEmpty) {
      return '';
    }

    if (_country.isoCode == 'RW') {
      final local = PhoneValidator.toRwandanLocal(trimmed);
      if (local != null) {
        return local;
      }
    }

    return trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  }

  void _syncRetryCountdown(int? retryAfterSeconds) {
    _retryTimer?.cancel();
    if (!mounted || retryAfterSeconds == null || retryAfterSeconds <= 0) {
      if (_retryCountdown != 0) {
        setState(() => _retryCountdown = 0);
      }
      return;
    }

    setState(() => _retryCountdown = retryAfterSeconds);
    _retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_retryCountdown <= 1) {
        timer.cancel();
        setState(() => _retryCountdown = 0);
        return;
      }
      setState(() => _retryCountdown -= 1);
    });
  }

  void _clearOtpInputs() {
    for (final controller in _otpControllers) {
      controller.clear();
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _sendCode() {
    if (_retryCountdown > 0) {
      return;
    }
    final raw = _phoneController.text.trim();
    final validationError = PhoneValidator.validateOtpPhone(raw, _country);
    if (validationError != null) {
      CoolToast.error(context, validationError);
      return;
    }
    final e164 = PhoneValidator.buildOtpE164Phone(raw, _country);
    ref.read(whatsAppOtpStateProvider.notifier).sendCode(e164);
  }

  Future<void> _verifyCode() async {
    if (_isVerifyingCode || ref.read(whatsAppOtpStateProvider).isLoading) {
      return;
    }

    final code = _otpControllers.map((c) => c.text.trim()).join();
    if (code.length != 6) {
      CoolToast.error(context, context.l10n.otpEnterAllDigits);
      return;
    }

    _isVerifyingCode = true;
    try {
      final result = await ref
          .read(whatsAppOtpStateProvider.notifier)
          .verifyCode(code);

      if (!mounted) {
        return;
      }

      if (result.isVerified) {
        // Establish the session in AuthNotifier.
        final signedIn = await ref
            .read(authProvider.notifier)
            .signInWithOtpSession(
              accessToken: result.accessToken!,
              refreshToken: result.refreshToken!,
            );

        if (!mounted) {
          return;
        }

        if (!signedIn) {
          CoolToast.error(
            context,
            ref.read(authProvider).error ?? context.l10n.otpSessionOpenFailed,
          );
          return;
        }

        CoolToast.success(context, context.l10n.otpPhoneVerified);
        Navigator.of(context, rootNavigator: true).pop(true);
      }
    } finally {
      _isVerifyingCode = false;
    }
  }

  void _goBack() {
    final otpState = ref.read(whatsAppOtpStateProvider);
    if (otpState.step == WhatsAppOtpStep.verifyCode) {
      ref.read(whatsAppOtpStateProvider.notifier).goBackToPhone();
      _clearOtpInputs();
    } else {
      Navigator.of(context, rootNavigator: true).pop(false);
    }
  }

  void _resendCode(WhatsAppOtpState otpState) {
    if (otpState.phone.isEmpty || otpState.isLoading || _retryCountdown > 0) {
      return;
    }
    _clearOtpInputs();
    ref.read(whatsAppOtpStateProvider.notifier).sendCode(otpState.phone);
  }

  @override
  Widget build(BuildContext context) {
    final otpState = ref.watch(whatsAppOtpStateProvider);
    final colors = context.coolSemanticColors;

    ref.listen<WhatsAppOtpState>(whatsAppOtpStateProvider, (prev, next) {
      if (next.retryAfterSeconds != prev?.retryAfterSeconds) {
        _syncRetryCountdown(next.retryAfterSeconds);
      }
    });

    return CoolScreenBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: CoolSpace.x5),
            child: otpState.step == WhatsAppOtpStep.enterPhone
                ? _buildPhoneStep(otpState, colors)
                : _buildVerifyStep(otpState, colors),
          ),
        ),
      ),
    );
  }

  // ── Step 1: Enter Phone ────────────────────────────────────────────

  Widget _buildPhoneStep(WhatsAppOtpState otpState, CoolSemanticColors colors) {
    final l10n = context.l10n;
    return Column(
      children: [
        // Back button row.
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: CoolSpace.x2),
            child: _BackChip(onTap: _goBack),
          ),
        ),

        const Spacer(flex: 2),

        // WhatsApp icon.
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: colors.accent.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: colors.accent.withValues(alpha: 0.15),
                blurRadius: 40,
                spreadRadius: 8,
              ),
            ],
          ),
          child: Icon(
            CoolIcons.chatBubble,
            size: 42,
            color: colors.accent,
          ),
        ),

        const SizedBox(height: CoolSpace.x6),

        // Title.
        Text(
          l10n.otpEnterWhatsappNumberTitle,
          textAlign: TextAlign.center,
          style: context.coolText.displayCondensed(
            Theme.of(context).textTheme.headlineMedium,
            fontWeight: FontWeight.w800,
            color: colors.primaryText,
            letterSpacing: -0.5,
          ),
        ),

        const SizedBox(height: CoolSpace.x3),

        Text(
          l10n.otpEnterWhatsappNumberSubtitle,
          textAlign: TextAlign.center,
          style: context.coolText.mono(
            Theme.of(context).textTheme.bodySmall,
            color: colors.accent,
            fontWeight: FontWeight.w500,
          ),
        ),

        const SizedBox(height: CoolSpace.x7),

        // Phone input row.
        Row(
          children: [
            // Country code chip.
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: colors.cardSurface,
                borderRadius: BorderRadius.circular(CoolRadii.md),
                border: Border.all(
                  color: colors.borderStrong.withValues(alpha: 0.55),
                ),
                boxShadow: CoolShadows.ambientFloat(strength: 0.22),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _country.flagEmoji,
                    style: context.coolText
                        .display(null, fontWeight: FontWeight.w500)
                        .copyWith(fontSize: 20),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _country.dialCode,
                    style: context.coolText.mono(
                      Theme.of(context).textTheme.bodyLarge,
                      color: colors.primaryText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    CoolIcons.dropDown,
                    color: colors.secondaryText,
                    size: 18,
                  ),
                ],
              ),
            ),

            const SizedBox(width: CoolSpace.x3),

            // Number field.
            Expanded(
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: colors.cardSurface,
                  borderRadius: BorderRadius.circular(CoolRadii.md),
                  border: Border.all(
                    color: colors.borderStrong.withValues(alpha: 0.55),
                  ),
                  boxShadow: CoolShadows.ambientFloat(strength: 0.22),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: context.coolText.mono(
                    Theme.of(context).textTheme.bodyLarge,
                    color: colors.primaryText,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.0,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: l10n.otpPhoneHint,
                    hintStyle: context.coolText.mono(
                      null,
                      color: colors.tertiaryText,
                      letterSpacing: 2.0,
                    ),
                    isCollapsed: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: CoolSpace.x7),

        if (otpState.error != null || _retryCountdown > 0) ...[
          _OtpStatusCard(
            message:
                otpState.error ?? context.l10n.resendCodeIn(_retryCountdown),
            accentColor: colors.accent,
          ),
          const SizedBox(height: CoolSpace.x4),
        ],

        // Send button.
        CoolButton(
          label: l10n.otpSendCodeUpper,
          variant: CoolButtonVariant.accent,
          size: CoolButtonSize.lg,
          isLoading: otpState.isLoading,
          onTap: otpState.isLoading || _retryCountdown > 0 ? null : _sendCode,
        ),

        if (_retryCountdown > 0) ...[
          const SizedBox(height: CoolSpace.x3),
          Text(
            l10n.resendCodeIn(_retryCountdown),
            textAlign: TextAlign.center,
            style: context.coolText.mono(
              Theme.of(context).textTheme.bodySmall,
              color: colors.secondaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],

        const Spacer(flex: 3),
      ],
    );
  }

  // ── Step 2: Verify OTP ─────────────────────────────────────────────

  Widget _buildVerifyStep(
    WhatsAppOtpState otpState,
    CoolSemanticColors colors,
  ) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back button.
        Padding(
          padding: const EdgeInsets.only(top: CoolSpace.x2),
          child: _BackChip(onTap: _goBack),
        ),

        const SizedBox(height: CoolSpace.x7),

        // Title.
        Text(
          l10n.otpVerifyTitle,
          style: context.coolText.displayCondensed(
            Theme.of(context).textTheme.headlineMedium,
            fontWeight: FontWeight.w800,
            color: colors.primaryText,
            letterSpacing: -0.5,
          ),
        ),

        const SizedBox(height: CoolSpace.x3),

        // Subtitle.
        RichText(
          text: TextSpan(
            style: context.coolText.mono(
              Theme.of(context).textTheme.bodySmall,
              color: colors.accent,
              fontWeight: FontWeight.w500,
            ),
            children: [
              TextSpan(text: l10n.otpVerifySubtitlePrefix),
              TextSpan(
                text: otpState.phone,
                style: context.coolText.mono(
                  null,
                  color: colors.primaryText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const TextSpan(text: '.'),
            ],
          ),
        ),

        if (otpState.error != null ||
            otpState.attemptsRemaining != null ||
            _retryCountdown > 0) ...[
          const SizedBox(height: CoolSpace.x4),
          _OtpStatusCard(
            message:
                otpState.error ?? context.l10n.resendCodeIn(_retryCountdown),
            secondaryMessage: otpState.attemptsRemaining == null
                ? null
                : 'Attempts remaining: ${otpState.attemptsRemaining}',
            accentColor: colors.accent,
          ),
        ],

        const SizedBox(height: CoolSpace.x8),

        // 6-digit OTP boxes.
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (index) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: index == 0 ? 0 : 4,
                  right: index == 5 ? 0 : 4,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 54),
                  child: AspectRatio(
                    aspectRatio: 50 / 64,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.cardSurface,
                        borderRadius: BorderRadius.circular(CoolRadii.md),
                        border: Border.all(
                          color: _otpControllers[index].text.isNotEmpty
                              ? colors.accentDeep.withValues(alpha: 0.72)
                              : colors.borderStrong.withValues(alpha: 0.52),
                          width: _otpControllers[index].text.isNotEmpty ? 1.4 : 0.9,
                        ),
                        boxShadow: CoolShadows.ambientFloat(strength: 0.18),
                      ),
                      child: TextField(
                        controller: _otpControllers[index],
                        focusNode: _otpFocusNodes[index],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: 1,
                        style: context.coolText.displayCondensed(
                          Theme.of(context).textTheme.headlineSmall,
                          fontWeight: FontWeight.w800,
                          color: colors.primaryText,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          counterText: '',
                          isCollapsed: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 16),
                        ),
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (value) {
                          setState(() {});
                          if (value.isNotEmpty && index < 5) {
                            _otpFocusNodes[index + 1].requestFocus();
                          }
                          if (value.isEmpty && index > 0) {
                            _otpFocusNodes[index - 1].requestFocus();
                          }
                          // Auto-verify when all 6 are filled.
                          final full = _otpControllers.every(
                            (c) => c.text.trim().isNotEmpty,
                          );
                          if (full) {
                            _verifyCode();
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),

        const Spacer(),

        // Verify button.
        CoolButton(
          label: l10n.otpVerifyButtonUpper,
          variant: CoolButtonVariant.accent,
          size: CoolButtonSize.lg,
          isLoading: otpState.isLoading,
          onTap: otpState.isLoading ? null : _verifyCode,
        ),

        const SizedBox(height: CoolSpace.x3),

        Center(
          child: TextButton(
            onPressed: otpState.isLoading || _retryCountdown > 0
                ? null
                : () => _resendCode(otpState),
            child: Text(
              _retryCountdown > 0
                  ? l10n.resendCodeIn(_retryCountdown)
                  : l10n.resendCode,
            ),
          ),
        ),

        const SizedBox(height: CoolSpace.x6),
      ],
    );
  }
}

// ── Back chip ────────────────────────────────────────────────────────

class _BackChip extends StatelessWidget {
  const _BackChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: colors.glassSurface,
          borderRadius: BorderRadius.circular(CoolRadii.md),
          border: Border.all(color: colors.borderStrong.withValues(alpha: 0.6)),
          boxShadow: CoolShadows.glass(strength: 0.28),
        ),
        child: Icon(
          CoolIcons.chevronLeft,
          color: colors.primaryText,
          size: 28,
        ),
      ),
    );
  }
}

class _OtpStatusCard extends StatelessWidget {
  const _OtpStatusCard({
    required this.message,
    required this.accentColor,
    this.secondaryMessage,
  });

  final String message;
  final String? secondaryMessage;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CoolSpace.x4),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.md),
        border: Border.all(color: accentColor.withValues(alpha: 0.35)),
        boxShadow: CoolShadows.ambientFloat(strength: 0.18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: context.coolText.mono(
              Theme.of(context).textTheme.bodySmall,
              color: colors.primaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (secondaryMessage != null) ...[
            const SizedBox(height: CoolSpace.x2),
            Text(
              secondaryMessage!,
              style: context.coolText.mono(
                Theme.of(context).textTheme.bodySmall,
                color: colors.secondaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
