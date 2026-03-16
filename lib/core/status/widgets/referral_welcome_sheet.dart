import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';

class ReferralWelcomeSheet extends StatelessWidget {
  const ReferralWelcomeSheet({
    required this.inviterName,
    required this.onAccept,
    super.key,
  });

  final String inviterName;
  final VoidCallback onAccept;

  static Future<void> show(
    BuildContext context, {
    required String inviterName,
    required VoidCallback onAccept,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ReferralWelcomeSheet(
        inviterName: inviterName,
        onAccept: onAccept,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: palette.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            '🤝',
            style: TextStyle(fontSize: 64),
          ),
          const SizedBox(height: 24),
          Text(
            'You\'re Invited!',
            style: GoogleFonts.dmSans(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 12),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: palette.text2,
              ),
              children: [
                const TextSpan(text: 'Your friend '),
                TextSpan(
                  text: inviterName,
                  style: TextStyle(
                    color: palette.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const TextSpan(text: ' invited you to join Cool.'),
              ],
            ),
          ),
          const SizedBox(height: 32),
          CoolCard(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.stars_rounded, color: palette.accent, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bonus Tokens Waiting',
                        style: GoogleFonts.dmSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: palette.text,
                        ),
                      ),
                      Text(
                        'Complete your first activity to earn 50 Cool Tokens.',
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: palette.text3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          CoolButton(
            label: 'Get Started',
            onTap: () {
              Navigator.pop(context);
              onAccept();
            },
          ),
        ],
      ),
    );
  }
}
