import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      title: 'Share group',
      subtitle: 'Share by link, QR code, chat app, SMS, or deep link.',
      children: [
        const InfoSecurityBanner(
          title: 'Group sharing',
          message:
              'The link does not include phone numbers, receiver MoMo numbers, or raw SMS.',
          tone: CollectStatusTone.privacy,
        ),
        CollectCard(
          child: Column(
            children: [
              CollectButton(
                label: 'SMS',
                icon: CollectIcons.sms,
                onPressed: () => _openShareTarget(
                  context,
                  Uri(scheme: 'sms', queryParameters: {'body': text}),
                  'SMS sharing is not available on this device.',
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
                ),
                variant: CollectButtonVariant.secondary,
                expand: true,
              ),
              CollectSpacing.gap12,
              CollectButton(
                label: 'Copy deep link',
                icon: CollectIcons.copy,
                onPressed: () => copyToClipboard(
                  context,
                  link,
                  message: 'Group deep link copied.',
                ),
                variant: CollectButtonVariant.secondary,
                expand: true,
              ),
            ],
          ),
        ),
        QRCard(
          link: link,
          caption:
              'Group link and QR code for chat apps, SMS, or in-person sharing.',
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
  ) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (launched || !context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(failureMessage)));
  }
}
