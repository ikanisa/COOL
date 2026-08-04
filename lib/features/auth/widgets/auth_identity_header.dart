part of 'auth_screen_widgets.dart';

class AuthIdentityHeader extends StatelessWidget {
  const AuthIdentityHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CollectBrandMark(
          framed: false,
          compact: true,
          foregroundColor: context.collectColors.onImagePrimary,
        ),
      ],
    );
  }
}

class AuthHeadline extends StatelessWidget {
  const AuthHeadline({
    required this.otpSent,
    required this.phone,
    required this.usesReviewAuth,
    super.key,
  });

  final bool otpSent;
  final String phone;
  final bool usesReviewAuth;

  @override
  Widget build(BuildContext context) {
    final foreground = context.collectColors.onImagePrimary;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          otpSent ? 'Verify WhatsApp' : 'Sign in',
          style: textTheme.headlineLarge?.copyWith(
            color: foreground,
            fontWeight: CollectTypography.weightBold,
            height: CollectTypography.leadingDense,
            letterSpacing: CollectTypography.trackingDefault,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        CollectSpacing.gap8,
        Text(
          otpSent
              ? usesReviewAuth
                    ? 'Use the reviewer code for $phone.'
                    : 'Code sent to $phone'
              : 'Enter your WhatsApp number to receive a secure sign-in code.',
          style: textTheme.bodyLarge?.copyWith(
            color: foreground.withValues(alpha: 0.70),
            fontWeight: CollectTypography.weightSemibold,
            letterSpacing: CollectTypography.trackingDefault,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
