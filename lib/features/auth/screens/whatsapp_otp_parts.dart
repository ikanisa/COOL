part of 'whatsapp_otp_screen.dart';

extension _WhatsAppOtpScreenSteps on _WhatsAppOtpScreenState {
  Widget _buildPhoneStep(WhatsAppOtpState otpState, CoolSemanticColors colors) {
    final l10n = context.l10n;
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: CoolSpace.x2),
            child: _BackChip(onTap: _goBack),
          ),
        ),
        const Spacer(flex: 2),
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
          child: Icon(CoolIcons.chatBubble, size: 42, color: colors.accent),
        ),
        const SizedBox(height: CoolSpace.x6),
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
        Row(
          children: [
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
                ],
              ),
            ),
            const SizedBox(width: CoolSpace.x3),
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
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    filled: false,
                    fillColor: Colors.transparent,
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

  Widget _buildVerifyStep(
    WhatsAppOtpState otpState,
    CoolSemanticColors colors,
  ) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: CoolSpace.x2),
          child: _BackChip(onTap: _goBack),
        ),
        const SizedBox(height: CoolSpace.x7),
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
                          width: _otpControllers[index].text.isNotEmpty
                              ? 1.4
                              : 0.9,
                        ),
                        boxShadow: CoolShadows.ambientFloat(strength: 0.18),
                      ),
                      child: TextField(
                        controller: _otpControllers[index],
                        focusNode: _otpFocusNodes[index],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: 6,
                        style: context.coolText.displayCondensed(
                          Theme.of(context).textTheme.headlineSmall,
                          fontWeight: FontWeight.w800,
                          color: colors.primaryText,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          focusedErrorBorder: InputBorder.none,
                          filled: false,
                          fillColor: Colors.transparent,
                          counterText: '',
                          isCollapsed: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 16),
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (value) {
                          final digits = value.replaceAll(
                            RegExp(r'[^0-9]'),
                            '',
                          );
                          if (digits.length > 1) {
                            _distributeOtpDigits(digits);
                            return;
                          }
                          _refreshOtpInputs();
                          if (value.isNotEmpty && index < 5) {
                            _otpFocusNodes[index + 1].requestFocus();
                          }
                          if (value.isEmpty && index > 0) {
                            _otpFocusNodes[index - 1].requestFocus();
                          }
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
        child: Icon(CoolIcons.chevronLeft, color: colors.primaryText, size: 28),
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
