import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../auth/providers/auth_provider.dart';

enum MomoSetupIntent {
  contribute,
  createGroup;

  String get missingProfileMessage => switch (this) {
    MomoSetupIntent.contribute =>
      'Set up your default MoMo in Settings before contributing.',
    MomoSetupIntent.createGroup =>
      'Set up your default MoMo in Settings before creating a group.',
  };
}

Future<bool> ensureMomoSetupForAction(
  BuildContext context,
  WidgetRef ref, {
  required MomoSetupIntent intent,
  String? redirectLocation,
}) async {
  final user = ref.read(authProvider).user;
  if (user?.hasMomoRecipient ?? false) {
    return true;
  }

  if (!context.mounted) {
    return false;
  }

  CoolToast.info(context, intent.missingProfileMessage);
  await context.push(
    AppRoutes.settingsWalletLocation(redirect: redirectLocation),
  );
  return false;
}
