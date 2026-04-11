import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/l10n.dart';
import '../../core/providers/engagement_providers.dart';
import '../../core/theme/cool_foundations.dart';
import 'cool_toast.dart';
import 'wa_button.dart';

/// A modal bottom sheet for sharing a group invite via QR code, copy link,
/// or WhatsApp.
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
    } else if (context.mounted) {
      CoolToast.error(context, 'WhatsApp is not available');
    }

    if (context.mounted) {
      Navigator.of(context).pop();
    }
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
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final textTheme = Theme.of(context).textTheme;
    final space = context.coolSpace;
    final radii = context.coolRadii;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.elevatedBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(radii.lg)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            space.x5 + 2,
            space.x3,
            space.x5 + 2,
            space.x5 + 2,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.borderStrong,
                  borderRadius: const BorderRadius.all(Radius.circular(2)),
                ),
              ),
              SizedBox(height: space.x5),
              Text(
                sheetTitle ?? 'Invite to $groupName',
                textAlign: TextAlign.center,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.primaryText,
                ),
              ),
              SizedBox(height: space.x1 + 2),
              Text(
                sheetSubtitle,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w400,
                  color: colors.tertiaryText,
                ),
              ),
              SizedBox(height: space.x6),
              Container(
                padding: const EdgeInsets.all(CoolSpace.x5 - 2),
                decoration: BoxDecoration(
                  color: colors.cardSurfaceStrong,
                  borderRadius: BorderRadius.all(Radius.circular(radii.md)),
                ),
                child: QrImageView(
                  data: inviteUrl,
                  version: QrVersions.auto,
                  size: 180,
                  eyeStyle: QrEyeStyle(
                    eyeShape: QrEyeShape.circle,
                    color: colors.primaryText,
                  ),
                  dataModuleStyle: QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.circle,
                    color: colors.primaryText,
                  ),
                  backgroundColor: Colors.transparent,
                ),
              ),
              SizedBox(height: space.x6),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: space.x3 + 2,
                  vertical: space.x3,
                ),
                decoration: BoxDecoration(
                  color: colors.cardSurface,
                  borderRadius: BorderRadius.all(Radius.circular(radii.xs)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        inviteUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.mono(
                          textTheme.bodySmall,
                          fontWeight: FontWeight.w400,
                          color: colors.secondaryText,
                        ),
                      ),
                    ),
                    SizedBox(width: space.x3 - 2),
                    Semantics(
                      button: true,
                      label: context.l10n.copyInviteLink,
                      child: GestureDetector(
                        onTap: () async {
                          await Clipboard.setData(
                            ClipboardData(text: inviteUrl),
                          );
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
                          padding: EdgeInsets.symmetric(
                            horizontal: space.x3 - 2,
                            vertical: space.x1 + 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.cardSurfaceStrong,
                            borderRadius: BorderRadius.all(
                              Radius.circular(radii.xs / 1.5),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.copy_rounded,
                                size: 14,
                                color: colors.accent,
                              ),
                              SizedBox(width: space.x1),
                              Text(
                                'Copy',
                                style: textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: colors.accent,
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
              SizedBox(height: space.x4 + 2),
              WaButton(onTap: () => _shareViaWhatsApp(context, ref)),
            ],
          ),
        ),
      ),
    );
  }
}
