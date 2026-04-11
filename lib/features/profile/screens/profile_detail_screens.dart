import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_market.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_floating_header_sliver.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/profile_view_provider.dart';
import '../widgets/profile_dialogs.dart';
import '../widgets/profile_momo_edit_sheet.dart';

class ProfileWalletScreen extends ConsumerWidget {
  const ProfileWalletScreen({this.redirectLocation, super.key});

  final String? redirectLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileViewProvider);

    return _ProfileDetailScaffold(
      title: context.l10n.profileWalletLabel,
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
            final redirect = redirectLocation?.trim();
            if (redirect != null && redirect.isNotEmpty) {
              context.go(redirect);
            } else {
              context.pop();
            }
          } else {
            CoolToast.error(context, context.l10n.profileMomoUpdateFailed);
          }
        },
        showSheetChrome: false,
      ),
    );
  }
}

class _ProfileDetailScaffold extends StatelessWidget {
  const _ProfileDetailScaffold({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final backTooltip = MaterialLocalizations.of(context).backButtonTooltip;
    return CoolScreenBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            CoolFloatingHeaderSliver(
              automaticallyImplyLeading: false,
              leading: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: backTooltip,
                icon: Icon(Icons.arrow_back_rounded, color: colors.primaryText),
              ),
              title: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: colors.primaryText),
              ),
            ),
          ],
          body: SafeArea(top: false, child: child),
        ),
      ),
    );
  }
}
