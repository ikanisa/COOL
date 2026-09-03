import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/repositories/collect_repository.dart';

/// Keep the pending action and its route intact while the user edits profile.
/// The repository and server independently recheck readiness on submission.
Future<void> requireMemberProfileReady(
  BuildContext context,
  WidgetRef ref,
) async {
  if (ref.read(collectRepositoryProvider).currentProfile?.isComplete == true) {
    return;
  }
  await context.push('/settings/profile');
  if (!context.mounted) return;
  if (ref.read(collectRepositoryProvider).currentProfile?.isComplete != true) {
    throw const FormatException('Complete your profile before continuing.');
  }
}
