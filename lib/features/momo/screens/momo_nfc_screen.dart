import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/app_market.dart';
import '../../../core/providers/app_access_provider.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/momo_service_provider.dart';
import '../widgets/momo_qr_nfc_widgets.dart';

class MomoNfcScreen extends ConsumerWidget {
  const MomoNfcScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.coolPalette;
    final user = ref.watch(authProvider).user;
    final country = AppMarket.country;
    final momoNumber = user?.momoNumber.isNotEmpty == true
        ? user!.momoNumber
        : user?.phone.isNotEmpty == true
        ? user!.phone
        : '';
    final momoCode = user?.momoCode;

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Icon(Icons.arrow_back_rounded, color: palette.text),
        ),
        title: Text(
          'NFC pay',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: palette.text,
          ),
        ),
      ),
      body: CoolScreenBackground(
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
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
