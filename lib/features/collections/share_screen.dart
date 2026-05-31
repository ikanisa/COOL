import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/env/app_env.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class ShareScreen extends ConsumerWidget {
  const ShareScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final env = ref.watch(appEnvProvider);
    final repo = ref.read(collectRepositoryProvider.notifier);
    final collection = repo.collectionById(collectionId);
    final baseUrl = env.publicUrl.isEmpty
        ? 'https://collect.rw'
        : env.publicUrl;
    final link = '$baseUrl/c/${collection.slug}';
    final text = [
      collection.title,
      collection.description,
      'Join or contribute: $link',
    ].where((line) => line.trim().isNotEmpty).join('\n');

    return ScreenScaffold(
      title: 'Share',
      subtitle: 'Link, QR, chat.',
      children: [
        CollectBottomSheet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CollectButton(
                label: 'SMS',
                icon: CollectIcons.sms,
                onPressed: () => _openShareTarget(
                  context,
                  Uri(scheme: 'sms', queryParameters: {'body': text}),
                  'SMS sharing is not available on this device.',
                  'SMS share opened',
                ),
                expand: true,
              ),
              CollectSpacing.gap12,
              CollectButton(
                label: 'WhatsApp',
                icon: CollectIcons.sms,
                onPressed: () => _openShareTarget(
                  context,
                  Uri.https('wa.me', '/', {'text': text}),
                  'WhatsApp sharing is not available on this device.',
                  'WhatsApp share opened',
                ),
                variant: CollectButtonVariant.secondary,
                expand: true,
              ),
              CollectSpacing.gap12,
              CollectButton(
                label: 'Copy deep link',
                icon: CollectIcons.copy,
                onPressed: () {
                  copyToClipboard(
                    context,
                    link,
                    message: 'Group deep link copied.',
                  );
                  context.go(
                    '/share/confirmed?message=Group%20deep%20link%20copied',
                  );
                },
                variant: CollectButtonVariant.secondary,
                expand: true,
              ),
              CollectSpacing.gap16,
              SelectableText(
                link,
                style: CollectTypography.mono(
                  context.collectColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        QRCard(
          link: link,
          caption: 'Share link or QR.',
          onCopy: () => copyToClipboard(
            context,
            text,
            message: 'Group share text copied.',
          ),
        ),
      ],
    );
  }

  Future<void> _openShareTarget(
    BuildContext context,
    Uri uri,
    String failureMessage,
    String successMessage,
  ) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted) return;
    if (launched) {
      context.go(
        '/share/confirmed?message=${Uri.encodeComponent(successMessage)}',
      );
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(failureMessage)));
  }
}
