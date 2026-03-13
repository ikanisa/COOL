import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/phone_validator.dart';
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
    final l10n = context.l10n;
    final displayNumber = PhoneValidator.formatMomoDisplay(momoNumber, country);
    return CoolCard(
      backgroundColor: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.sendMoney,
            style: GoogleFonts.dmSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Launches ${country.name} MoMo USSD to complete the transfer.',
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
                  'From $displayNumber',
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
          CoolButton(label: l10n.sendMoney, onTap: onSendTap),
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
    required this.country,
    required this.momoNumber,
    required this.onOpenStatements,
    required this.onOpenQrCode,
    required this.onRequestPayment,
    required this.onScanQr,
    required this.onOpenNfcTools,
    super.key,
  });

  final CoolCountry country;
  final String momoNumber;
  final VoidCallback onOpenStatements;
  final VoidCallback onOpenQrCode;
  final VoidCallback onRequestPayment;
  final VoidCallback onScanQr;
  final VoidCallback onOpenNfcTools;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final displayNumber = PhoneValidator.formatMomoDisplay(momoNumber, country);
    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.moreToolsSectionTitle,
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Statements, QR, and NFC tools for your Mobile Money profile.',
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
            subtitle: 'Review wallet and savings activity.',
            onTap: onOpenStatements,
          ),
          const Divider(height: 1, color: AppColors.border),
          MomoToolRow(
            icon: Icons.qr_code_2_rounded,
            title: 'MoMo QR',
            subtitle: displayNumber,
            onTap: onOpenQrCode,
          ),
          const Divider(height: 1, color: AppColors.border),
          MomoToolRow(
            icon: Icons.request_page_rounded,
            title: 'Request payment',
            subtitle: 'Create a MoMo pay link for SMS or WhatsApp.',
            onTap: onRequestPayment,
          ),
          const Divider(height: 1, color: AppColors.border),
          MomoToolRow(
            icon: Icons.center_focus_strong_rounded,
            title: 'Scan QR',
            subtitle: 'Launch payment-ready QR and prefill recipient QR.',
            onTap: onScanQr,
          ),
          const Divider(height: 1, color: AppColors.border),
          MomoToolRow(
            icon: Icons.nfc_rounded,
            title: 'NFC tools',
            subtitle: 'Share or scan payment-ready NFC details.',
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
