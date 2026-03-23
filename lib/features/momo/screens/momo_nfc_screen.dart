import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_market.dart';
import '../../../core/providers/app_access_provider.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/momo_service_provider.dart';
import '../widgets/momo_qr_nfc_widgets.dart';
import '../../../core/l10n/l10n.dart';

class MomoNfcScreen extends ConsumerWidget {
  const MomoNfcScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final user = ref.watch(authProvider).user;
    final country = AppMarket.country;
    final momoNumber = user?.momoNumber.isNotEmpty == true
        ? user!.momoNumber
        : user?.phone.isNotEmpty == true
        ? user!.phone
        : '';
    final momoCode = user?.momoCode;

    return Scaffold(
      backgroundColor: colors.appBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: context.l10n.back,
          icon: Icon(Icons.arrow_back_rounded, color: colors.primaryText),
        ),
        title: Text(
          'NFC pay',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.primaryText,
          ),
        ),
      ),
      body: CoolScreenBackground(
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              CoolSpace.x4 + CoolSpace.x1 / 2,
              CoolSpace.x2,
              CoolSpace.x4 + CoolSpace.x1 / 2,
              CoolSpace.x6,
            ),
            children: [
              MomoNfcCard(
                country: country,
                momoNumber: momoNumber,
                momoCode: momoCode,
                momoService: ref.read(momoServiceProvider),
                appAccessService: ref.read(appAccessServiceProvider),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
