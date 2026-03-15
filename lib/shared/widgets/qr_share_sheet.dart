import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/engagement_providers.dart';
import '../../core/theme/app_colors.dart';
import 'cool_toast.dart';
import 'wa_button.dart';

/// A modal bottom sheet for sharing a group invite via QR code, copy link,
/// or WhatsApp.
///
/// Use the static [show] helper to present this sheet:
/// ```dart
/// QrShareSheet.show(context, groupName: 'My Group', inviteUrl: 'https://…');
/// ```
class QrShareSheet extends ConsumerWidget {
  const QrShareSheet({
    required this.groupName,
    required this.inviteUrl,
    this.sheetTitle,
    this.sheetSubtitle = 'Scan QR or share the link',
    this.shareText,
    this.analyticsTargetType,
    super.key,
  });

  final String groupName;
  final String inviteUrl;
  final String? sheetTitle;
  final String sheetSubtitle;
  final String? shareText;
  final String? analyticsTargetType;

  /// Show the sheet as a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required String groupName,
    required String inviteUrl,
    String? sheetTitle,
    String sheetSubtitle = 'Scan QR or share the link',
    String? shareText,
    String? analyticsTargetType,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => QrShareSheet(
        groupName: groupName,
        inviteUrl: inviteUrl,
        sheetTitle: sheetTitle,
        sheetSubtitle: sheetSubtitle,
        shareText: shareText,
        analyticsTargetType: analyticsTargetType,
      ),
    );
  }

  Future<void> _shareViaWhatsApp(BuildContext context, WidgetRef ref) async {
    final encodedText = Uri.encodeComponent(
      shareText ?? 'Join $groupName on Cool: $inviteUrl',
    );
    final waUrl = Uri.parse('https://wa.me/?text=$encodedText');
    if (await canLaunchUrl(waUrl)) {
      await launchUrl(waUrl, mode: LaunchMode.externalApplication);
      if (_targetType == 'group_invite') {
        await ref
            .read(engagementTrackerProvider)
            .trackInviteSent(
              channel: 'whatsapp',
              inviteUrl: inviteUrl,
              targetType: _targetType,
            );
      }
      await ref
          .read(engagementTrackerProvider)
          .trackShareAction(
            channel: 'whatsapp',
            targetType: _targetType,
            targetUrl: inviteUrl,
          );
    } else {
      if (context.mounted) {
        CoolToast.error(context, 'WhatsApp is not available');
      }
    }
    if (context.mounted) Navigator.of(context).pop();
  }

  String get _targetType {
    if (analyticsTargetType != null && analyticsTargetType!.trim().isNotEmpty) {
      return analyticsTargetType!.trim();
    }

    final uri = Uri.tryParse(inviteUrl);
    if (uri == null) {
      return 'unknown';
    }

    final segments = uri.pathSegments.where((segment) => segment.isNotEmpty);
    if (segments.contains('invite')) {
      return 'group_invite';
    }
    return 'share_link';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Handle bar ──────────────────────────────────────────
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              // ── Title ───────────────────────────────────────────────
              Text(
                sheetTitle ?? 'Invite to $groupName',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                sheetSubtitle,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.text3,
                ),
              ),
              const SizedBox(height: 24),

              // ── QR Code ─────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surface3,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: QrImageView(
                  data: inviteUrl,
                  version: QrVersions.auto,
                  size: 180,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.circle,
                    color: Colors.white,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.circle,
                    color: Colors.white,
                  ),
                  backgroundColor: Colors.transparent,
                ),
              ),
              const SizedBox(height: 24),

              // ── Invite URL row ──────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        inviteUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.dmMono(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: AppColors.text2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Semantics(
                      button: true,
                      label: 'Copy invite link',
                      child: GestureDetector(
                        onTap: () async {
                          Clipboard.setData(ClipboardData(text: inviteUrl));
                          if (_targetType == 'group_invite') {
                            await ref
                                .read(engagementTrackerProvider)
                                .trackInviteSent(
                                  channel: 'copy_link',
                                  inviteUrl: inviteUrl,
                                  targetType: _targetType,
                                );
                          }
                          await ref
                              .read(engagementTrackerProvider)
                              .trackShareAction(
                                channel: 'copy_link',
                                targetType: _targetType,
                                targetUrl: inviteUrl,
                              );
                          if (!context.mounted) {
                            return;
                          }
                          CoolToast.success(context, 'Link copied!');
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surface3,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.copy_rounded,
                                size: 14,
                                color: AppColors.accent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Copy',
                                style: GoogleFonts.dmSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ── WhatsApp share button ───────────────────────────────
              WaButton(
                label: 'Share via WhatsApp',
                onTap: () => _shareViaWhatsApp(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
