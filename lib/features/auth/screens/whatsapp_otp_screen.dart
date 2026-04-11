import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_market.dart';
import '../../../core/config/country_catalog.dart';
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
  const WhatsAppOtpScreen({super.key});

  /// Show as a full-screen route pushed on top of current navigator.
  static Future<bool?> show(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const WhatsAppOtpScreen(),
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

  @override
  void initState() {
    super.initState();
    // Reset OTP state on open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(whatsAppOtpStateProvider.notifier).reset();
    });
  }

  @override
  void dispose() {
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

  void _sendCode() {
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
    final code = _otpControllers.map((c) => c.text.trim()).join();
    if (code.length != 6) {
      CoolToast.error(context, 'Enter all 6 digits');
      return;
    }

    final result = await ref
        .read(whatsAppOtpStateProvider.notifier)
        .verifyCode(code);

    if (!mounted) return;

    if (result.isVerified) {
      // Establish the session in AuthNotifier.
      await ref
          .read(authProvider.notifier)
          .signInWithOtpSession(
            accessToken: result.accessToken!,
            refreshToken: result.refreshToken!,
          );

      if (mounted) {
        CoolToast.success(context, 'Phone verified!');
        Navigator.of(context, rootNavigator: true).pop(true);
      }
    }
  }

  void _goBack() {
    final otpState = ref.read(whatsAppOtpStateProvider);
    if (otpState.step == WhatsAppOtpStep.verifyCode) {
      ref.read(whatsAppOtpStateProvider.notifier).goBackToPhone();
      // Clear OTP inputs.
      for (final c in _otpControllers) {
        c.clear();
      }
    } else {
      Navigator.of(context, rootNavigator: true).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final otpState = ref.watch(whatsAppOtpStateProvider);
    final colors = context.coolSemanticColors;

    // Show error toast reactively.
    ref.listen<WhatsAppOtpState>(whatsAppOtpStateProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        CoolToast.error(context, next.error!);
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
            Icons.chat_bubble_rounded,
            size: 42,
            color: colors.accent,
          ),
        ),

        const SizedBox(height: CoolSpace.x6),

        // Title.
        Text(
          'Enter WhatsApp\nNumber',
          textAlign: TextAlign.center,
          style: context.coolText.displayCondensed(
            Theme.of(context).textTheme.headlineMedium,
            fontWeight: FontWeight.w700,
            color: colors.primaryText,
            letterSpacing: -0.5,
          ),
        ),

        const SizedBox(height: CoolSpace.x3),

        Text(
          'Enter WhatsApp number to receive OTP',
          textAlign: TextAlign.center,
          style: context.coolText.mono(
            Theme.of(context).textTheme.bodySmall,
            color: colors.accent,
            fontWeight: FontWeight.w400,
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
                    style: context.coolText.display(
                      null,
                      fontWeight: FontWeight.w400,
                    ).copyWith(fontSize: 20),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _country.dialCode,
                    style: context.coolText.mono(
                      Theme.of(context).textTheme.bodyLarge,
                      color: colors.primaryText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_drop_down,
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
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.0,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: '788 123 456',
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

        // Send button.
        CoolButton(
          label: 'SEND CODE',
          variant: CoolButtonVariant.accent,
          size: CoolButtonSize.lg,
          isLoading: otpState.isLoading,
          onTap: otpState.isLoading ? null : _sendCode,
        ),

        const Spacer(flex: 3),
      ],
    );
  }

  // ── Step 2: Verify OTP ─────────────────────────────────────────────

  Widget _buildVerifyStep(
    WhatsAppOtpState otpState,
    CoolSemanticColors colors,
  ) {
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
          'Verify OTP',
          style: context.coolText.displayCondensed(
            Theme.of(context).textTheme.headlineMedium,
            fontWeight: FontWeight.w700,
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
              fontWeight: FontWeight.w400,
            ),
            children: [
              const TextSpan(
                text: 'We sent a 6-digit OTP to your WhatsApp at ',
              ),
              TextSpan(
                text: otpState.phone,
                style: context.coolText.mono(
                  null,
                  color: colors.primaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const TextSpan(text: '.'),
            ],
          ),
        ),

        const SizedBox(height: CoolSpace.x8),

        // 6-digit OTP boxes.
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (index) {
            return SizedBox(
              width: 50,
              height: 64,
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
                    fontWeight: FontWeight.w700,
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
            );
          }),
        ),

        const Spacer(),

        // Verify button.
        CoolButton(
          label: 'VERIFY',
          variant: CoolButtonVariant.accent,
          size: CoolButtonSize.lg,
          isLoading: otpState.isLoading,
          onTap: otpState.isLoading ? null : _verifyCode,
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
          Icons.chevron_left_rounded,
          color: colors.primaryText,
          size: 28,
        ),
      ),
    );
  }
}
