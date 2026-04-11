import 'package:flutter/material.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../models/biopay_profile.dart';

/// A confirmation sheet shown before launching the MoMo dialer after a
/// successful BioPay face match. Ensures the user can verify the payee
/// identity before any payment action.
class BiopayPayeeConfirmationSheet extends StatelessWidget {
  const BiopayPayeeConfirmationSheet({
    required this.profile,
    required this.matchScore,
    super.key,
  });

  final BiopayProfile profile;
  final double matchScore;

  /// Shows the confirmation sheet and returns `true` if the user taps PAY.
  static Future<bool> show(
    BuildContext context, {
    required BiopayProfile profile,
    required double matchScore,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (_) => BiopayPayeeConfirmationSheet(
        profile: profile,
        matchScore: matchScore,
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final confidenceLabel = _confidenceLabel(matchScore);
    final confidenceColor = _confidenceColor(matchScore, colors);

    return Container(
      margin: const EdgeInsets.all(CoolSpace.x4),
      padding: const EdgeInsets.all(CoolSpace.x5),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong,
        borderRadius: BorderRadius.circular(CoolRadii.xl),
        boxShadow: CoolShadows.ambientFloat(strength: 0.6),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.tertiaryText.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: CoolSpace.x5),

            // Payee avatar
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [colors.accent, colors.info]),
                borderRadius: BorderRadius.circular(CoolRadii.lg),
              ),
              alignment: Alignment.center,
              child: Text(
                _initials(profile.displayName),
                style: text.displayCondensed(
                  Theme.of(context).textTheme.headlineMedium,
                  fontWeight: FontWeight.w800,
                  color: colors.accentForeground,
                ),
              ),
            ),
            const SizedBox(height: CoolSpace.x4),

            // Payee name
            Text(
              profile.displayName.toUpperCase(),
              textAlign: TextAlign.center,
              style: text.displayCondensed(
                Theme.of(context).textTheme.titleLarge,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: CoolSpace.x2),

            // Masked recipient
            Text(
              '${profile.routeLabel} • ${profile.maskedRecipientValue}',
              style: text.mono(
                Theme.of(context).textTheme.bodyMedium,
                color: colors.secondaryText,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: CoolSpace.x3),

            // Match confidence
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: CoolSpace.x3,
                vertical: CoolSpace.x2,
              ),
              decoration: BoxDecoration(
                color: confidenceColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(CoolRadii.pill),
              ),
              child: Text(
                confidenceLabel,
                style: text.mono(
                  Theme.of(context).textTheme.labelSmall,
                  color: confidenceColor,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: CoolSpace.x6),

            // Action buttons
            CoolButton(
              label: 'PAY THIS PERSON',
              onTap: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: CoolSpace.x3),
            CoolButton(
              label: 'CANCEL',
              variant: CoolButtonVariant.secondary,
              onTap: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  String _confidenceLabel(double score) {
    final pct = (score * 100).round();
    if (score >= 0.90) return 'HIGH CONFIDENCE • $pct%';
    if (score >= 0.80) return 'GOOD MATCH • $pct%';
    return 'MATCH • $pct%';
  }

  Color _confidenceColor(double score, CoolSemanticColors colors) {
    if (score >= 0.90) return colors.success;
    if (score >= 0.80) return colors.accent;
    return colors.warning;
  }
}
