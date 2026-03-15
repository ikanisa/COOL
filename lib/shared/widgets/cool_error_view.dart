import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/cool_palette.dart';
import 'cool_button.dart';

/// Standardized error view used throughout the app.
///
/// Displays a centered message with an optional icon and retry button.
class CoolErrorView extends StatelessWidget {
  const CoolErrorView({
    required this.message,
    this.onRetry,
    this.icon = Icons.error_outline_rounded,
    this.compact = false,
    super.key,
  });

  /// User-facing error message.
  final String message;

  /// Called when the user taps the retry button. If null, no button is shown.
  final VoidCallback? onRetry;

  /// Icon displayed above the message.
  final IconData icon;

  /// If true, renders in a more compact layout (for inline use in lists).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final iconSize = compact ? 36.0 : 52.0;
    final spacing = compact ? 12.0 : 20.0;

    return Semantics(
      label: 'Error: $message',
      liveRegion: true,
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 32,
            vertical: compact ? 16 : 48,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Container(
                  width: iconSize + 20,
                  height: iconSize + 20,
                  decoration: BoxDecoration(
                    color: palette.red.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: iconSize, color: palette.red),
                ),
              ),
              SizedBox(height: spacing),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                  fontSize: compact ? 14 : 16,
                  color: palette.text2,
                  height: 1.5,
                ),
              ),
              if (onRetry != null) ...[
                SizedBox(height: spacing + 4),
                CoolButton(
                  label: 'Try Again',
                  onTap: onRetry!,
                  variant: CoolButtonVariant.secondary,
                  fullWidth: false,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
