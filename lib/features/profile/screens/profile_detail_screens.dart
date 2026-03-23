import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_market.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../auth/providers/auth_provider.dart';
import 'kyc_id_scan_screen.dart';
import '../providers/profile_view_provider.dart';
import '../widgets/profile_dialogs.dart';
import '../widgets/profile_momo_edit_sheet.dart';
import '../widgets/profile_travel_role_sheet.dart';

class ProfileWalletScreen extends ConsumerWidget {
  const ProfileWalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileViewProvider);

    return _ProfileDetailScaffold(
      title: context.l10n.profileMobileMoney,
      child: ProfileMomoEditSheet(
        currentMomoNumber: profile.momoNumber,
        currentMomoCode: profile.momoCode,
        currentMomoRouteType: profile.effectiveMomoRouteType,
        country: AppMarket.country,
        onSubmitted: (result) async {
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) => ProfileBlockingProgressDialog(
              message: context.l10n.profileSavingMomoInfo,
            ),
          );

          final success = await ref
              .read(authProvider.notifier)
              .updateMomoInfo(
                momoNumber: result.momoNumber,
                momoCode: result.momoCode,
                momoRouteType: result.momoRouteType,
                country: result.countryCode,
              );

          if (!context.mounted) {
            return;
          }
          Navigator.of(context, rootNavigator: true).pop();

          if (success) {
            CoolToast.success(context, context.l10n.profileMomoUpdated);
            context.pop();
          } else {
            CoolToast.error(context, context.l10n.profileMomoUpdateFailed);
          }
        },
        showSheetChrome: false,
      ),
    );
  }
}

class ProfileIdentityScreen extends ConsumerWidget {
  const ProfileIdentityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const KycIdScanScreen();
  }
}

class ProfileTravelRoleScreen extends ConsumerWidget {
  const ProfileTravelRoleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileViewProvider);

    return _ProfileDetailScaffold(
      title: context.l10n.profileTravelRoleLabel,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
      child: ProfileTravelRoleSheet(
        profile: profile,
        onOpenPassengerTools: profile.momoLinked
            ? null
            : () => context.push(AppRoutes.profileWallet),
        onOpenDriverSetup: () => context.push(AppRoutes.mobilityDriver),
      ),
    );
  }
}

class _ProfileDetailScaffold extends StatelessWidget {
  const _ProfileDetailScaffold({
    required this.title,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final String title;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.coolSemanticColors.appBackground,
      appBar: AppBar(title: Text(title)),
      body: CoolScreenBackground(
        child: SafeArea(
          top: false,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
