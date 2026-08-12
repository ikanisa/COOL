import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/env/app_env.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/utils/collect_share_links.dart';
import '../../shared/utils/collect_share_origin.dart';

String groupDeepLinkFor(AppEnv env, CollectCollection collection) {
  return collectPublicLink(env, ['c', collection.slug.trim()]);
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
        sharePositionOrigin: collectSharePositionOrigin(context),
        downloadFallbackEnabled: true,
      ),
    );
  } catch (_) {
    await Clipboard.setData(
      ClipboardData(text: groupDeepLinkFor(env, collection)),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Group link copied.')));
  }
}

Future<void> copyGroupDeepLink({
  required BuildContext context,
  required WidgetRef ref,
  required CollectCollection collection,
}) async {
  final link = groupDeepLinkFor(ref.read(appEnvProvider), collection);
  await Clipboard.setData(ClipboardData(text: link));
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('Group link copied.')));
}
