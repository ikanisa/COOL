import 'package:flutter/material.dart';

import '../../../app/theme/collect_colors.dart';
import '../../../app/theme/collect_component_tokens.dart';
import '../../../app/theme/collect_runtime_tokens.dart';
import '../../../app/theme/collect_spacing.dart';
import '../../../app/theme/collect_universal_tokens.dart';

/// A shared provider action. The caller owns availability and sign-in behavior.
class CollectGoogleSignInButton extends StatelessWidget {
  const CollectGoogleSignInButton({
    required this.onPressed,
    this.busy = false,
    super.key,
  });

  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final tokens = context.collectUniversalTokens;
    final enabled = onPressed != null && !busy;
    final label = busy ? 'Connecting to Google' : 'Continue with Google';
    return SizedBox(
      width: double.infinity,
      child: MergeSemantics(
        child: Semantics(
          liveRegion: busy,
          child: OutlinedButton(
            onPressed: enabled ? onPressed : null,
            style: CollectComponentTokens.outlinedButton(context).copyWith(
              minimumSize: const WidgetStatePropertyAll(
                Size(CollectSpacing.target, CollectSpacing.target),
              ),
              backgroundColor: WidgetStatePropertyAll(colors.surfaceReadable),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.disabled)
                    ? colors.textMuted
                    : colors.textPrimary,
              ),
              side: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.focused)) {
                  return BorderSide(
                    color: tokens.focusRing,
                    width: tokens.focusRingWidth,
                  );
                }
                return BorderSide(
                  color: states.contains(WidgetState.disabled)
                      ? colors.textMuted
                      : CollectRuntimeTokens.controlBorder(colors),
                  width: tokens.highContrast ? 2 : 1,
                );
              }),
            ),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: const BoxDecoration(
                    color: CollectColors.publicWhite,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox.square(
                    dimension: CollectSpacing.x8,
                    child: Center(
                      child: Image.asset(
                        'assets/auth/google_g.png',
                        width: CollectSpacing.x5,
                        height: CollectSpacing.x5 * 204 / 200,
                        fit: BoxFit.contain,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                ),
                CollectSpacing.gapW12,
                Expanded(
                  child: Builder(
                    builder: (context) => DefaultTextStyle(
                      // Material actions otherwise inherit a single-line label.
                      style: DefaultTextStyle.of(context).style,
                      textAlign: TextAlign.center,
                      softWrap: true,
                      overflow: TextOverflow.visible,
                      child: Text(label),
                    ),
                  ),
                ),
                CollectSpacing.gapW12,
                SizedBox.square(
                  dimension: CollectSpacing.x8,
                  child: busy
                      ? Center(
                          child: ExcludeSemantics(
                            child: SizedBox.square(
                              dimension: CollectSpacing.x5,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
