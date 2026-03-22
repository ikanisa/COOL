import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_palette.dart';

// ═════════════════════════════════════════════════════════════════════════════
// SIGN OUT DIALOG
// ═════════════════════════════════════════════════════════════════════════════

class ProfileSignOutDialog extends StatelessWidget {
  const ProfileSignOutDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final l10n = context.l10n;
    return AlertDialog(
      backgroundColor: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: palette.border),
      ),
      title: Text(
        l10n.signOutAction,
        style: GoogleFonts.dmSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: palette.text,
        ),
      ),
      content: Text(
        l10n.signOutMessage,
        style: GoogleFonts.dmSans(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: palette.text2,
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            l10n.cancelAction,
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: palette.text2,
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            l10n.signOutAction,
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: palette.red,
            ),
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// DELETE ACCOUNT DIALOG
// ═════════════════════════════════════════════════════════════════════════════

class ProfileDeleteAccountDialog extends StatelessWidget {
  const ProfileDeleteAccountDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final l10n = context.l10n;
    return AlertDialog(
      backgroundColor: palette.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        l10n.deleteAccountQuestion,
        style: GoogleFonts.dmSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: palette.text,
        ),
      ),
      content: Text(
        l10n.deleteAccountMessage,
        style: GoogleFonts.dmSans(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: palette.text2,
          height: 1.45,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            l10n.cancelAction,
            style: GoogleFonts.dmSans(
              fontWeight: FontWeight.w700,
              color: palette.text2,
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            l10n.delete,
            style: GoogleFonts.dmSans(
              fontWeight: FontWeight.w800,
              color: palette.red,
            ),
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// BLOCKING PROGRESS DIALOG
// ═════════════════════════════════════════════════════════════════════════════

class ProfileBlockingProgressDialog extends StatelessWidget {
  const ProfileBlockingProgressDialog({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return AlertDialog(
      backgroundColor: palette.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      content: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CupertinoActivityIndicator(radius: 11),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: palette.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

