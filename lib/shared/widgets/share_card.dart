import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers/app_access_provider.dart';
import '../../core/theme/cool_foundations.dart';
import 'contact_picker_sheet.dart';
import 'qr_share_sheet.dart';

/// A reusable share card that provides WhatsApp + native share + QR code.
///
/// Use this on detail screens to let users share deep-linked content.
class ShareCard extends ConsumerWidget {
  const ShareCard({
    required this.title,
    required this.shareUrl,
    this.subtitle,
    this.message,
    this.shareText,
    this.icon = Icons.link_rounded,
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

  /// Alias for [subtitle]
  final String? message;

  /// The deep-link URL to share
  final String shareUrl;

  /// Pre-formatted share text (URL is appended automatically)
  final String? shareText;

  /// Leading icon
  final IconData icon;

  /// Optional custom QR sheet title
  final String? sheetTitle;

  /// Optional custom QR sheet subtitle
  final String? sheetSubtitle;

  /// Optional analytics target name for engagement tracking
  final String? analyticsTargetType;

  /// Optional async share URL resolver used to create referral links.
  final Future<String> Function()? resolveShareUrl;

  String? get _effectiveSubtitle => subtitle ?? message;

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
      sheetSubtitle:
          sheetSubtitle ?? _effectiveSubtitle ?? 'Scan QR or share the link',
      shareText: '${shareText ?? title}\n$resolvedUrl',
      analyticsTargetType: analyticsTargetType,
    );
  }

  Future<void> _shareLink() async {
    final resolvedUrl = await _resolvedShareUrl();
    final text = shareText ?? title;
    await SharePlus.instance.share(ShareParams(text: '$text\n$resolvedUrl'));
  }

  Future<void> _shareViaContacts(BuildContext context, WidgetRef ref) async {
    final contacts = await ContactPickerSheet.show(
      context,
      appAccessService: ref.read(appAccessServiceProvider),
      multiSelect: false,
      title: 'Share via Contact',
      message: 'Select a contact to share with',
    );

    if (contacts.isEmpty) return;

    final resolvedUrl = await _resolvedShareUrl();
    final text = shareText ?? title;
    await SharePlus.instance.share(ShareParams(text: '$text\n$resolvedUrl'));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(CoolSpace.x4),
      decoration: BoxDecoration(
        color: colors.elevatedBackground,
        borderRadius: BorderRadius.circular(CoolRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: colors.secondaryText),
              const SizedBox(width: CoolSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.primaryText,
                      ),
                    ),
                    if (_effectiveSubtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _effectiveSubtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w400,
                          color: colors.tertiaryText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x3),
          Row(
            children: [
              // WhatsApp / QR share
              Expanded(
                child: _ShareButton(
                  icon: Icons.qr_code_rounded,
                  label: 'QR / Share',
                  colors: colors,
                  onTap: () {
                    _openQrSheet(context);
                  },
                ),
              ),
              const SizedBox(width: CoolSpace.x2),
              // Native share
              Expanded(
                child: _ShareButton(
                  icon: Icons.share_rounded,
                  label: 'Share',
                  colors: colors,
                  onTap: () {
                    _shareLink();
                  },
                ),
              ),
              const SizedBox(width: CoolSpace.x2),
              // Contacts share
              Expanded(
                child: _ShareButton(
                  icon: Icons.contacts_rounded,
                  label: 'Contacts',
                  colors: colors,
                  onTap: () => _shareViaContacts(context, ref),
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
    required this.colors,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final CoolSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: colors.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(CoolRadii.sm),
            border: Border.all(color: colors.accent.withValues(alpha: 0.25)),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(CoolRadii.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CoolSpace.x2,
                vertical: CoolSpace.x3,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.max,
                children: [
                  Icon(icon, size: 18, color: colors.accent),
                  const SizedBox(width: CoolSpace.x2),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w400,
                        color: colors.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
