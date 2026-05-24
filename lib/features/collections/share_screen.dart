import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/env/app_env.dart';
import '../../core/utils/money_format.dart';
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
      if (collection.targetAmountRwf != null)
        'Target: ${formatRwf(collection.targetAmountRwf!)}',
      'Contribute via MOMO: $link',
      'Collect does not move money; you pay the receiver directly.',
    ].join('\n');

    return ScreenScaffold(
      title: 'Share',
      subtitle:
          'Share a safe collection link. Receiver MOMO details are shown only in the contribution step.',
      children: [
        const InfoSecurityBanner(
          title: 'Safe share',
          message:
              'This link can be public. It does not include phone numbers, receiver MOMO numbers, or raw SMS.',
          tone: CollectStatusTone.privacy,
        ),
        QRCard(
          link: link,
          caption: 'Safe collection link for WhatsApp, QR, or public posts.',
          onCopy: () => copyToClipboard(
            context,
            text,
            message: 'WhatsApp share text copied.',
          ),
        ),
      ],
    );
  }
}
