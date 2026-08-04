import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/env/app_env.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/utils/collect_share_origin.dart';

String collectAppInviteLinkFor(AppEnv env, CollectProfile? profile) {
  final configured = env.publicUrl.trim();
  final base = configured.isEmpty ? defaultCollectPublicUrl : configured;
  final cleanBase = base.replaceFirst(RegExp(r'/$'), '');
  final publicId = profile?.publicId.trim();
  if (publicId != null && publicId.isNotEmpty) {
    return '$cleanBase/invite/${Uri.encodeComponent(publicId)}';
  }
  return '$cleanBase/app';
}

String collectAppShareMessageFor(AppEnv env, CollectProfile? profile) {
  final link = collectAppInviteLinkFor(env, profile);
  return 'Join me on Collect for group contributions in Rwanda: $link';
}

Future<void> shareCollectApp({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  final env = ref.read(appEnvProvider);
  final profile = ref.read(collectRepositoryProvider).currentProfile;
  final link = collectAppInviteLinkFor(env, profile);
  final message = collectAppShareMessageFor(env, profile);

  try {
    await SharePlus.instance.share(
      ShareParams(
        title: 'Collect',
        text: message,
        sharePositionOrigin: collectSharePositionOrigin(context),
        downloadFallbackEnabled: true,
      ),
    );
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: link));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Collect invite link copied.')),
    );
  }
}
