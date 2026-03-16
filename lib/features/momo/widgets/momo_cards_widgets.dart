import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/cool_palette.dart';

// ═════════════════════════════════════════════════════════════════════════════
// MOMO ACTION GRID
// ═════════════════════════════════════════════════════════════════════════════

class MomoActionGrid extends StatelessWidget {
  const MomoActionGrid({
    required this.onOpenStatements,
    required this.onScanQr,
    required this.onOpenQrCode,
    required this.onRequestPayment,
    required this.onOpenNfcTools,
    super.key,
  });

  final VoidCallback onOpenStatements;
  final VoidCallback onScanQr;
  final VoidCallback onOpenQrCode;
  final VoidCallback onRequestPayment;
  final VoidCallback onOpenNfcTools;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.1,
      children: [
        MomoActionCard(
          icon: Icons.receipt_long_rounded,
          title: 'Statements',
          onTap: onOpenStatements,
        ),
        MomoActionCard(
          icon: Icons.center_focus_strong_rounded,
          title: 'Scan QR',
          onTap: onScanQr,
          isPrimary: true,
        ),
        MomoActionCard(
          icon: Icons.qr_code_2_rounded,
          title: 'MOMO QR',
          onTap: onOpenQrCode,
        ),
        MomoActionCard(
          icon: Icons.request_page_rounded,
          title: 'Request',
          onTap: onRequestPayment,
        ),
        MomoActionCard(
          icon: Icons.nfc_rounded,
          title: 'NFC pay',
          onTap: onOpenNfcTools,
        ),
      ],
    );
  }
}

class MomoActionCard extends StatelessWidget {
  const MomoActionCard({
    required this.icon,
    required this.title,
    required this.onTap,
    this.isPrimary = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Semantics(
      button: true,
      label: title,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isPrimary ? palette.accent : palette.surface2,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isPrimary ? palette.accent : palette.border,
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 28,
                color: isPrimary ? Colors.white : palette.text,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isPrimary ? Colors.white : palette.text,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MomoToolRow extends StatelessWidget {
  const MomoToolRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      hint: 'Open $title',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: palette.surface2,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 20, color: palette.text),
                ),
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
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: palette.text2,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: palette.text3,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
