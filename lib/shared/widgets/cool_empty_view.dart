import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/cool_palette.dart';

/// Standardized empty-state view for screens and lists with no data.
///
/// Displays a centered icon and message. Optionally includes an action
/// button for the user to take next steps (e.g. "Create your first trip").
class CoolEmptyView extends StatelessWidget {
  const CoolEmptyView({
    required this.message,
    this.icon = Icons.inbox_rounded,
    this.action,
    this.actionLabel,
    this.compact = false,
    super.key,
  });

  /// User-facing empty-state message.
  final String message;

  /// Icon displayed above the message.
  final IconData icon;

  /// Optional callback for the action button.
  final VoidCallback? action;

  /// Label for the action button. Required if [action] is provided.
  final String? actionLabel;

  /// If true, renders in a more compact layout.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final iconSize = compact ? 36.0 : 48.0;
    final spacing = compact ? 12.0 : 20.0;

    return Semantics(
      container: true,
      label: message,
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
                    color: palette.surface3,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: iconSize, color: palette.text3),
                ),
              ),
              SizedBox(height: spacing),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                  fontSize: compact ? 14 : 16,
                  color: palette.text3,
                  height: 1.5,
                ),
              ),
              if (action != null && actionLabel != null) ...[
                SizedBox(height: spacing + 4),
                TextButton(
                  onPressed: action,
                  style: TextButton.styleFrom(
                    foregroundColor: palette.accent,
                    textStyle: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
