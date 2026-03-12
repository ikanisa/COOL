import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';

// ═════════════════════════════════════════════════════════════════════════════
// SEND MONEY CARD
// ═════════════════════════════════════════════════════════════════════════════

class MomoSendMoneyCard extends StatelessWidget {
  const MomoSendMoneyCard({
    required this.country,
    required this.momoNumber,
    required this.onSendTap,
    super.key,
  });

  final CoolCountry country;
  final String momoNumber;
  final VoidCallback onSendTap;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      backgroundColor: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Send money',
            style: GoogleFonts.dmSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Opens ${country.name} USSD.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${country.displayName} · ${country.currencyCode}',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'From $momoNumber',
                  style: GoogleFonts.dmMono(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CoolButton(label: 'Send money', onTap: onSendTap),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// MOMO TOOLS CARD
// ═════════════════════════════════════════════════════════════════════════════

class MomoToolsCard extends StatelessWidget {
  const MomoToolsCard({
    required this.momoNumber,
    required this.onOpenStatements,
    required this.onOpenQrCode,
    required this.onOpenNfcTools,
    super.key,
  });

  final String momoNumber;
  final VoidCallback onOpenStatements;
  final VoidCallback onOpenQrCode;
  final VoidCallback onOpenNfcTools;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'More tools',
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Statements, QR code, and NFC.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          MomoToolRow(
            icon: Icons.receipt_long_rounded,
            title: 'Statements',
            subtitle: 'Wallet and savings activity',
            onTap: onOpenStatements,
          ),
          const Divider(height: 1, color: AppColors.border),
          MomoToolRow(
            icon: Icons.qr_code_2_rounded,
            title: 'My QR code',
            subtitle: momoNumber,
            onTap: onOpenQrCode,
          ),
          const Divider(height: 1, color: AppColors.border),
          MomoToolRow(
            icon: Icons.nfc_rounded,
            title: 'NFC tools',
            subtitle: 'Read or write payment tags',
            onTap: onOpenNfcTools,
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// MOMO TOOL ROW
// ═════════════════════════════════════════════════════════════════════════════

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
    return InkWell(
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
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 20, color: AppColors.text),
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
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AppColors.text2,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: AppColors.text3,
            ),
          ],
        ),
      ),
    );
  }
}
