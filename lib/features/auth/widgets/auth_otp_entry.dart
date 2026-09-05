part of 'auth_screen_widgets.dart';

class AuthOtpEntry extends StatelessWidget {
  const AuthOtpEntry({
    required this.controller,
    required this.onChanged,
    super.key,
  });

  static const digitCount = 6;

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = colors.authForeground;
    return AutofillGroup(
      child: Semantics(
        textField: true,
        label: 'Verification code',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: foreground.withValues(alpha: 0.14)),
          ),
          child: TextField(
            key: const ValueKey('auth_otp_digit_0'),
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            autofillHints: const [AutofillHints.oneTimeCode],
            enableSuggestions: false,
            autocorrect: false,
            obscureText: true,
            obscuringCharacter: '•',
            textInputAction: TextInputAction.done,
            textAlign: TextAlign.center,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(digitCount),
            ],
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: foreground,
              fontWeight: CollectTypography.weightSemibold,
              fontFeatures: const [FontFeature.tabularFigures()],
              letterSpacing: CollectTypography.trackingCollectId,
            ),
            decoration: InputDecoration(
              hintText: '••••••',
              hintStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: foreground.withValues(alpha: 0.32),
                letterSpacing: CollectTypography.trackingCollectId,
              ),
              counterText: '',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 17,
              ),
            ),
            onChanged: (_) => onChanged(),
          ),
        ),
      ),
    );
  }
}
