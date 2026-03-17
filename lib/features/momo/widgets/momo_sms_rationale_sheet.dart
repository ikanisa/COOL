import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_button.dart';

class MomoSmsRationaleSheet extends StatelessWidget {
  const MomoSmsRationaleSheet({
    required this.onAccept,
    required this.onDecline,
    super.key,
  });

  final VoidCallback onAccept;
  final VoidCallback onDecline;

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onAccept,
    required VoidCallback onDecline,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          MomoSmsRationaleSheet(onAccept: onAccept, onDecline: onDecline),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: palette.border2,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: palette.accentGlow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.sms_rounded, color: palette.accent, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Sync your M-Money statements',
                  style: GoogleFonts.dmSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: palette.text,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'If you opt in',
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: palette.text2,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          const _RationalePoint(
            icon: Icons.history_rounded,
            title: 'Deep historical sync',
            message:
                'First-time setup imports M-Money confirmations '
                'from the past year. Only messages from approved '
                'Mobile Money senders are read — all other SMS '
                'is ignored.',
          ),
          const SizedBox(height: 16),
          const _RationalePoint(
            icon: Icons.security_rounded,
            title: 'Privacy focused',
            message:
                'Cool only reads messages from approved M-Money '
                'sender IDs (e.g. M-Money, MoMo). Your personal '
                'conversations and other SMS are never accessed.',
          ),
          const SizedBox(height: 16),
          const _RationalePoint(
            icon: Icons.sync_rounded,
            title: 'Always in sync',
            message:
                'New M-Money confirmations are detected in '
                'real time and automatically matched to your '
                'group contributions, subscriptions, and partner '
                'transactions.',
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: CoolButton(
                  label: 'Maybe later',
                  variant: CoolButtonVariant.secondary,
                  onTap: () {
                    Navigator.pop(context);
                    onDecline();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CoolButton(
                  label: 'Allow access',
                  onTap: () {
                    Navigator.pop(context);
                    onAccept();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RationalePoint extends StatelessWidget {
  const _RationalePoint({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: palette.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: palette.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                message,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: palette.text2,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
