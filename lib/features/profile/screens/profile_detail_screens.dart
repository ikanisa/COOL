import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_market.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/profile_view_provider.dart';
import '../widgets/profile_dialogs.dart';
import '../widgets/profile_momo_edit_sheet.dart';

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
    final profile = ref.watch(profileViewProvider);
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;

    Widget buildRow(String label, String value) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: CoolSpace.x2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 132,
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.tertiaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final rows = <Widget>[
      buildRow(
        'Official name',
        profile.officialName.isNotEmpty ? profile.officialName : 'Not set',
      ),
      buildRow(
        'Official phone',
        profile.officialPhone.isNotEmpty ? profile.officialPhone : 'Not set',
      ),
      buildRow(
        'Date of birth',
        profile.dateOfBirth?.trim().isNotEmpty == true
            ? profile.dateOfBirth!.trim()
            : 'Not set',
      ),
      buildRow('National ID', profile.maskedNationalId ?? 'Not set'),
    ];

    return _ProfileDetailScaffold(
      title: 'Personal Info',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: [
          CoolCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Official details on file',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: CoolSpace.x2),
                Text(
                  'These details are used for account ownership and bank-custodied savings records.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.secondaryText,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: CoolSpace.x4),
                ...rows,
              ],
            ),
          ),
        ],
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
    return Scaffold(
      backgroundColor: context.coolSemanticColors.appBackground,
      appBar: AppBar(title: Text(title)),
      body: CoolScreenBackground(child: SafeArea(top: false, child: child)),
    );
  }
}
