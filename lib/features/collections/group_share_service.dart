import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/env/app_env.dart';
import '../../shared/models/collect_models.dart';

String groupDeepLinkFor(AppEnv env, CollectCollection collection) {
  final configured = env.publicUrl.trim();
  final base = configured.isEmpty ? defaultCollectPublicUrl : configured;
  return '${base.replaceFirst(RegExp(r'/$'), '')}/c/${collection.slug}';
}

String groupShareMessageFor(AppEnv env, CollectCollection collection) {
  final link = groupDeepLinkFor(env, collection);
  return 'Join ${collection.title} for ${collection.collectionType.shortPurpose.toLowerCase()} on Collect: $link';
}

Future<void> shareGroupDeepLink({
  required BuildContext context,
  required WidgetRef ref,
  required CollectCollection collection,
}) async {
  final env = ref.read(appEnvProvider);
  final message = groupShareMessageFor(env, collection);
  try {
    await SharePlus.instance.share(
      ShareParams(
        title: collection.title,
        text: message,
        downloadFallbackEnabled: true,
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Open on your phone to share via apps.')),
    );
  }
}
