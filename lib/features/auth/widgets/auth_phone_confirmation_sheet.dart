part of 'auth_screen_widgets.dart';

class AuthPhoneConfirmationSheet extends StatelessWidget {
  const AuthPhoneConfirmationSheet({required this.phone, super.key});

  final String phone;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Material(
      color: CollectColors.referenceContentDark,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(CollectRadius.cardLarge),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          CollectSpacing.x5,
          CollectSpacing.x3,
          CollectSpacing.x5,
          CollectSpacing.x5 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textMuted.withValues(alpha: 0.42),
                  borderRadius: CollectRadius.pillBorder,
                ),
              ),
            ),
            CollectSpacing.gap24,
            Text(
              'Confirm your number',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: colors.onImagePrimary,
                fontWeight: CollectTypography.weightBold,
              ),
            ),
            CollectSpacing.gap8,
            Text(
              'We will send a six-digit sign-in code on WhatsApp to',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.onImagePrimary.withValues(alpha: 0.68),
              ),
            ),
            CollectSpacing.gap12,
            SelectableText(
              phone,
              key: const ValueKey('auth_confirmation_phone'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: colors.onImagePrimary,
                fontWeight: CollectTypography.weightBold,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            CollectSpacing.gap24,
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: colors.onImagePrimary,
                foregroundColor: CollectColors.referenceChromeBlack,
                shape: const StadiumBorder(),
              ),
              child: const Text('Confirm and send'),
            ),
            CollectSpacing.gap12,
            FilledButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: colors.onImagePrimary.withValues(alpha: 0.14),
                foregroundColor: colors.onImagePrimary,
                shape: const StadiumBorder(),
              ),
              child: const Text('Edit number'),
            ),
          ],
        ),
      ),
    );
  }
}
