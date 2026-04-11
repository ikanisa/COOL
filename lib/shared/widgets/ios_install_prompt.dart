import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/cool_foundations.dart';

/// iOS Add-to-Home-Screen guided onboarding prompt.
///
/// On iOS Safari, there is no native `beforeinstallprompt` event.
/// This widget displays a branded bottom sheet instructing the user
/// to use Safari's Share → "Add to Home Screen" flow.
///
/// Show after meaningful engagement (e.g., order placed or 2+ items
/// browsed), never on first paint.
///
/// Usage:
/// ```dart
/// if (IosInstallPrompt.shouldShow(context)) {
///   IosInstallPrompt.show(context);
/// }
/// ```
class IosInstallPrompt extends StatelessWidget {
  const IosInstallPrompt._();

  /// Whether the current environment is iOS Safari *and* not already in
  /// standalone mode (i.e., not already installed as a PWA).
  static bool shouldShow(BuildContext context) {
    if (!kIsWeb) return false;

    final platform = Theme.of(context).platform;
    if (platform != TargetPlatform.iOS) return false;

    // On Flutter Web, we can't directly detect standalone mode without
    // dart:html/dart:js_interop, but this guard at least limits to web+iOS.
    return true;
  }

  /// Shows the guided install bottom sheet.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const IosInstallPrompt._(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: EdgeInsets.only(
        left: space.x4,
        right: space.x4,
        bottom: MediaQuery.of(context).viewPadding.bottom + space.x4,
      ),
      decoration: BoxDecoration(
        color: colors.overlaySurface,
        borderRadius: BorderRadius.circular(CoolRadii.xxl),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.shadowColor.withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(space.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Drag handle ──────────────────────────────────────────
            Container(
              width: 36,
              height: 4,
              margin: EdgeInsets.only(bottom: space.x5),
              decoration: BoxDecoration(
                color: colors.tertiaryText.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // ── App icon ─────────────────────────────────────────────
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                CoolIcons.install,
                color: colors.accent,
                size: 28,
              ),
            ),
            SizedBox(height: space.x4),

            // ── Title ────────────────────────────────────────────────
            Text(
              context.l10n.pwaInstallCool,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.primaryText,
              ),
            ),
            SizedBox(height: space.x2),

            // ── Subtitle ─────────────────────────────────────────────
            Text(
              context.l10n.iosInstallSubtitle,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: colors.secondaryText,
                height: 1.45,
              ),
            ),
            SizedBox(height: space.x6),

            // ── Step 1 ───────────────────────────────────────────────
            _InstructionStep(
              step: '1',
              icon: CoolIcons.iosShare,
              text: context.l10n.iosInstallStep1,
              colors: colors,
              textTheme: textTheme,
            ),
            SizedBox(height: space.x4),

            // ── Step 2 ───────────────────────────────────────────────
            _InstructionStep(
              step: '2',
              icon: CoolIcons.addBox,
              text: context.l10n.iosInstallStep2,
              colors: colors,
              textTheme: textTheme,
            ),
            SizedBox(height: space.x4),

            // ── Step 3 ───────────────────────────────────────────────
            _InstructionStep(
              step: '3',
              icon: CoolIcons.checkCircle,
              text: context.l10n.iosInstallStep3,
              colors: colors,
              textTheme: textTheme,
            ),
            SizedBox(height: space.x6),

            // ── Dismiss button ───────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: space.x4),
                ),
                child: Text(
                  context.l10n.iosInstallGotIt,
                  style: textTheme.labelLarge?.copyWith(
                    color: colors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstructionStep extends StatelessWidget {
  const _InstructionStep({
    required this.step,
    required this.icon,
    required this.text,
    required this.colors,
    required this.textTheme,
  });

  final String step;
  final IconData icon;
  final String text;
  final CoolSemanticColors colors;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Step number badge
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: colors.accent.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            step,
            style: textTheme.labelSmall?.copyWith(
              color: colors.accent,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Icon
        Icon(icon, size: 20, color: colors.accent),
        const SizedBox(width: 10),
        // Text
        Expanded(
          child: Text(
            text,
            style: textTheme.bodyMedium?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
