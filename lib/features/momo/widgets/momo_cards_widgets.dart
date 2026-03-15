import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_palette.dart';
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
    final palette = context.coolPalette;
    final displayNumber = PhoneValidator.formatMomoDisplay(momoNumber, country);
    final hasDisplayNumber = displayNumber.trim().isNotEmpty;
    return Semantics(
      container: true,
      label: hasDisplayNumber
          ? 'Send money card. ${country.displayName} account $displayNumber. Uses ${country.currencyCode}.'
          : 'Send money card. ${country.displayName}. Uses ${country.currencyCode}.',
      child: CoolCard(
        backgroundColor: palette.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.sendMoney,
                style: GoogleFonts.dmSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: palette.text,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Launches ${country.name} MoMo USSD to complete the transfer.',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: palette.text2,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
              label: hasDisplayNumber
                  ? 'Source account ${country.displayName}. Currency ${country.currencyCode}. From $displayNumber.'
                  : 'Source account ${country.displayName}. Currency ${country.currencyCode}.',
              child: ExcludeSemantics(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: palette.surface2,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: palette.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${country.displayName} · ${country.currencyCode}',
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: palette.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasDisplayNumber
                            ? 'From $displayNumber'
                            : 'Use your registered Rwanda line to finish the payment.',
                        style: GoogleFonts.dmMono(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: palette.text2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            CoolButton(label: l10n.sendMoney, onTap: onSendTap),
          ],
        ),
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
    final palette = context.coolPalette;
    final displayNumber = PhoneValidator.formatMomoDisplay(momoNumber, country);
    final hasDisplayNumber = displayNumber.trim().isNotEmpty;
    return Semantics(
      container: true,
      label: hasDisplayNumber
          ? 'Mobile Money tools for $displayNumber.'
          : 'Mobile Money tools for Rwanda.',
      child: CoolCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.moreToolsSectionTitle,
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: palette.text,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Statements, scan, and extra receive tools for your Rwanda Mobile Money profile.',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: palette.text2,
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
            Divider(height: 1, color: palette.border),
            MomoToolRow(
              icon: Icons.qr_code_2_rounded,
              title: 'Full-screen QR',
              subtitle: hasDisplayNumber
                  ? 'Open your receive QR for $displayNumber.'
                  : 'Open your receive QR after adding your 07... number.',
              onTap: onOpenQrCode,
            ),
            Divider(height: 1, color: palette.border),
            MomoToolRow(
              icon: Icons.request_page_rounded,
              title: 'Request payment',
              subtitle: 'Create a Rwanda MoMo pay link for SMS or WhatsApp.',
              onTap: onRequestPayment,
            ),
            Divider(height: 1, color: palette.border),
            MomoToolRow(
              icon: Icons.center_focus_strong_rounded,
              title: 'Scan QR',
              subtitle: 'Launch payment-ready QR and prefill recipient QR.',
              onTap: onScanQr,
            ),
            Divider(height: 1, color: palette.border),
            MomoToolRow(
              icon: Icons.nfc_rounded,
              title: 'NFC tools',
              subtitle: 'Share or scan payment-ready NFC details.',
              onTap: onOpenNfcTools,
            ),
          ],
        ),
      ),
    );
  }
}

class MomoPaymentSafetyCard extends StatelessWidget {
  const MomoPaymentSafetyCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.coolPalette;
    return Semantics(
      container: true,
      label:
          '${l10n.momoTrustCardTitle}. ${l10n.momoTrustFeesTitle}. ${l10n.momoTrustApprovalTitle}. ${l10n.momoTrustReceiptTitle}.',
      child: CoolCard(
        backgroundColor: palette.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.momoTrustCardTitle,
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: palette.text,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.momoTrustCardSubtitle,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: palette.text2,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            const _MomoTrustRow(
              icon: Icons.visibility_rounded,
              titleKey: _MomoTrustRowKey.fees,
            ),
            const SizedBox(height: 12),
            const _MomoTrustRow(
              icon: Icons.verified_user_rounded,
              titleKey: _MomoTrustRowKey.approval,
            ),
            const SizedBox(height: 12),
            const _MomoTrustRow(
              icon: Icons.receipt_long_rounded,
              titleKey: _MomoTrustRowKey.receipt,
            ),
          ],
        ),
      ),
    );
  }
}

class MomoInboxSyncCard extends StatelessWidget {
  const MomoInboxSyncCard({
    required this.isAndroidSmsAvailable,
    required this.isSyncing,
    required this.onSyncTap,
    super.key,
  });

  final bool isAndroidSmsAvailable;
  final bool isSyncing;
  final VoidCallback onSyncTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final headline = isAndroidSmsAvailable
        ? 'Inbox-backed sync'
        : 'Inbox sync is Android-only';
    final buttonLabel = isSyncing ? 'Syncing inbox...' : 'Sync SMS';

    return Semantics(
      container: true,
      label:
          '$headline. First sync imports the last 12 months. Live listening sends each new M-Money SMS to Supabase. Sync SMS rescans the inbox for anything missed.',
      child: CoolCard(
        backgroundColor: palette.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              headline,
              style: GoogleFonts.dmSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: palette.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isAndroidSmsAvailable
                  ? 'First-time setup imports the last 12 months of M-Money inbox messages. After that, new M-Money SMS are forwarded to Supabase immediately.'
                  : 'COOL can keep M-Money statements in sync from the device inbox on Android. iPhone users can still use USSD, QR, and statements already stored on the server.',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: palette.text2,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            const _MomoInboxSyncStep(
              icon: Icons.history_rounded,
              title: 'First sync',
              subtitle: 'Import M-Money SMS from the last 12 months.',
            ),
            const SizedBox(height: 10),
            const _MomoInboxSyncStep(
              icon: Icons.sms_rounded,
              title: 'Live listening',
              subtitle: 'Each new M-Money SMS is sent to Supabase right away.',
            ),
            const SizedBox(height: 10),
            const _MomoInboxSyncStep(
              icon: Icons.sync_rounded,
              title: 'Manual catch-up',
              subtitle: 'Use Sync SMS anytime to rescan the inbox for misses.',
            ),
            const SizedBox(height: 16),
            AbsorbPointer(
              absorbing: !isAndroidSmsAvailable || isSyncing,
              child: Opacity(
                opacity: isAndroidSmsAvailable ? 1 : 0.6,
                child: CoolButton(
                  label: buttonLabel,
                  onTap: onSyncTap,
                  isLoading: isSyncing,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// MOMO TOOL ROW
// ═════════════════════════════════════════════════════════════════════════════

class _MomoInboxSyncStep extends StatelessWidget {
  const _MomoInboxSyncStep({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: palette.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.border),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: palette.text),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: palette.text,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: palette.text3,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
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
      hint: 'Double tap to open $title',
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

enum _MomoTrustRowKey { fees, approval, receipt }

class _MomoTrustRow extends StatelessWidget {
  const _MomoTrustRow({required this.icon, required this.titleKey});

  final IconData icon;
  final _MomoTrustRowKey titleKey;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.coolPalette;
    final (title, subtitle) = switch (titleKey) {
      _MomoTrustRowKey.fees => (
        l10n.momoTrustFeesTitle,
        l10n.momoTrustFeesSubtitle,
      ),
      _MomoTrustRowKey.approval => (
        l10n.momoTrustApprovalTitle,
        l10n.momoTrustApprovalSubtitle,
      ),
      _MomoTrustRowKey.receipt => (
        l10n.momoTrustReceiptTitle,
        l10n.momoTrustReceiptSubtitle,
      ),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: palette.accentGlow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.border),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: palette.accent),
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
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
