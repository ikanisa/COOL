import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_colors.dart';
import 'contact_picker_sheet.dart';
import 'qr_share_sheet.dart';

/// A reusable share card that provides WhatsApp + native share + QR code.
///
/// Use this on detail screens to let users share deep-linked content.
class ShareCard extends StatelessWidget {
  const ShareCard({
    required this.title,
    required this.shareUrl,
    this.subtitle,
    this.shareText,
    this.emoji = '🔗',
    this.sheetTitle,
    this.sheetSubtitle,
    this.analyticsTargetType,
    this.resolveShareUrl,
    super.key,
  });

  /// Card title (e.g. "Share this match")
  final String title;

  /// Optional subtitle
  final String? subtitle;

  /// The deep-link URL to share
  final String shareUrl;

  /// Pre-formatted share text (URL is appended automatically)
  final String? shareText;

  /// Leading emoji
  final String emoji;

  /// Optional custom QR sheet title
  final String? sheetTitle;

  /// Optional custom QR sheet subtitle
  final String? sheetSubtitle;

  /// Optional analytics target name for engagement tracking
  final String? analyticsTargetType;

  /// Optional async share URL resolver used to create referral links.
  final Future<String> Function()? resolveShareUrl;

  Future<String> _resolvedShareUrl() async {
    return await resolveShareUrl?.call() ?? shareUrl;
  }

  Future<void> _openQrSheet(BuildContext context) async {
    final resolvedUrl = await _resolvedShareUrl();
    if (!context.mounted) {
      return;
    }

    await QrShareSheet.show(
      context,
      groupName: title,
      inviteUrl: resolvedUrl,
      sheetTitle: sheetTitle,
      sheetSubtitle: sheetSubtitle ?? subtitle ?? 'Scan QR or share the link',
      shareText: '${shareText ?? title}\n$resolvedUrl',
      analyticsTargetType: analyticsTargetType,
    );
  }

  Future<void> _shareLink() async {
    final resolvedUrl = await _resolvedShareUrl();
    final text = shareText ?? title;
    await SharePlus.instance.share(ShareParams(text: '$text\n$resolvedUrl'));
  }

  Future<void> _shareViaContacts(BuildContext context) async {
    final contacts = await ContactPickerSheet.show(
      context,
      multiSelect: false,
      title: 'Share via Contact',
      subtitle: 'Select a contact to share with',
    );

    if (contacts.isEmpty) return;

    final resolvedUrl = await _resolvedShareUrl();
    final text = shareText ?? title;
    await SharePlus.instance.share(ShareParams(text: '$text\n$resolvedUrl'));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
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
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: AppColors.text3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // WhatsApp / QR share
              Expanded(
                child: _ShareButton(
                  icon: Icons.qr_code_rounded,
                  label: 'QR / Share',
                  onTap: () {
                    _openQrSheet(context);
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Native share
              Expanded(
                child: _ShareButton(
                  icon: Icons.share_rounded,
                  label: 'Share',
                  onTap: () {
                    _shareLink();
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Contacts share
              Expanded(
                child: _ShareButton(
                  icon: Icons.contacts_rounded,
                  label: 'Contacts',
                  onTap: () => _shareViaContacts(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShareButton extends StatelessWidget {
  const _ShareButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: AppColors.accent),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
