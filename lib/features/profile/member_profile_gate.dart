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

/// Group identity/membership does not require a wallet or payment profile.
/// The repository/server still recheck active own session and invitation scope.
void requireMemberGroupProfileReady(WidgetRef ref) {
  final profile = ref.read(collectRepositoryProvider).currentProfile;
  if (profile == null) throw StateError('Sign in before joining a group.');
}
