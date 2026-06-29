part of 'auth_screen_widgets.dart';

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
          otpSent
              ? usesReviewAuth
                    ? 'Use the reviewer code for $phone.'
                    : 'Code sent to $phone'
              : 'Use your WhatsApp number.',
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
