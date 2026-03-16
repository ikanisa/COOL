import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';

/// A section header row with a bold title and an optional trailing action.
///
/// ```dart
/// SectionTitle(
///   title: 'My Groups',
///   actionLabel: 'See all',
///   action: () => context.push('/groups'),
/// )
/// ```
class SectionTitle extends StatelessWidget {
  const SectionTitle({
    required this.title,
    this.actionLabel,
    this.onAction,
    this.action,
    super.key,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) {
    final effectiveAction = onAction ?? action;
    return Semantics(
      header: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: GoogleFonts.dmSans(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          if (actionLabel != null)
            Semantics(
              button: true,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                child: GestureDetector(
                  onTap: effectiveAction,
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: Text(
                      actionLabel!,
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
