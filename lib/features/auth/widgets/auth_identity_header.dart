part of 'auth_screen_widgets.dart';

class AuthIdentityHeader extends StatelessWidget {
  const AuthIdentityHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: IconButton(
        key: const ValueKey('auth_back_button'),
        tooltip: 'Back',
        onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/');
          }
        },
        style: IconButton.styleFrom(
          foregroundColor: context.collectColors.authForeground,
          backgroundColor: CollectColors.transparentColor,
          padding: EdgeInsets.zero,
        ),
        icon: const Icon(Icons.arrow_back_rounded, size: 30),
      ),
    );
  }
}

class AuthHeadline extends StatelessWidget {
  const AuthHeadline({
    required this.otpSent,
    required this.phone,
    this.useEmail = false,
    this.googlePending = false,
    super.key,
  });

  final bool otpSent;
  final String phone;
  final bool useEmail;
  final bool googlePending;

  @override
  Widget build(BuildContext context) {
    final foreground = context.collectColors.authForeground;
    final textTheme = Theme.of(context).textTheme;
    final usesAccessibilityText =
        MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          googlePending
              ? 'Continue with Google'
              : otpSent
              ? '6-digit code'
              : "Let's get started!",
          style: textTheme.headlineLarge?.copyWith(
            color: foreground,
            fontWeight: CollectTypography.weightBold,
            height: CollectTypography.leadingDense,
            letterSpacing: CollectTypography.trackingDefault,
          ),
          maxLines: usesAccessibilityText || otpSent ? null : 2,
          overflow: usesAccessibilityText
              ? TextOverflow.visible
              : TextOverflow.ellipsis,
        ),
        CollectSpacing.gap8,
        Text(
          googlePending
              ? 'Complete sign-in in your browser, then return to Collect.'
              : otpSent
              ? 'Enter the ${useEmail ? 'email' : 'WhatsApp'} code for $phone.'
              : useEmail
              ? 'Enter your email address. We will send a secure sign-in code.'
              : 'Enter your phone number. We will send a secure sign-in code on WhatsApp.',
          style: textTheme.bodyLarge?.copyWith(
            color: foreground.withValues(alpha: 0.70),
            fontWeight: CollectTypography.weightSemibold,
            letterSpacing: CollectTypography.trackingDefault,
          ),
          maxLines: usesAccessibilityText || otpSent ? null : 2,
          overflow: usesAccessibilityText
              ? TextOverflow.visible
              : TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
