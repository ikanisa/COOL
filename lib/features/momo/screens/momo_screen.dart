import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/providers/supported_countries_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../auth/providers/auth_provider.dart';
import '../widgets/momo_cards_widgets.dart';
import '../widgets/momo_qr_nfc_widgets.dart';
import '../widgets/momo_send_sheet.dart';

/// Mobile Money hub — USSD gateway, QR code, and NFC transfers.
class MomoScreen extends ConsumerWidget {
  const MomoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final countryCode = ref.watch(currentUserCountryCodeProvider);
    final countries =
        ref.watch(supportedCountriesProvider).valueOrNull ??
        CoolCountryCatalog.all;
    final country = CoolCountryCatalog.resolve(
      country: countryCode,
      phone: user?.phone,
      providerId: user?.momoProvider,
      source: countries,
    );
    final momoNumber = user?.momoNumber.isNotEmpty == true
        ? user!.momoNumber
        : user?.phone.isNotEmpty == true
        ? user!.phone
        : country.buildE164Phone('91234567');
    final momoCode = user?.momoCode;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: context.canPop(),
        title: Text(
          'Mobile Money',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
      ),
      body: CoolScreenBackground(
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 96),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: 8),
                  MomoSendMoneyCard(
                    country: country,
                    momoNumber: momoNumber,
                    onSendTap: () => _showSendMoneySheet(
                      context,
                      country: country,
                      momoNumber: momoNumber,
                      momoCode: momoCode,
                    ),
                  ),
                  const SizedBox(height: 16),
                  MomoToolsCard(
                    momoNumber: momoNumber,
                    onOpenStatements: () =>
                        context.push(AppRoutes.momoStatements),
                    onOpenQrCode: () => _showQrCodeSheet(
                      context,
                      country: country,
                      momoNumber: momoNumber,
                      momoCode: momoCode,
                    ),
                    onOpenNfcTools: () => _showNfcToolsSheet(
                      context,
                      currencyCode: country.currencyCode,
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showQrCodeSheet(
    BuildContext context, {
    required CoolCountry country,
    required String momoNumber,
    String? momoCode,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MomoQrSheet(
        country: country,
        momoNumber: momoNumber,
        momoCode: momoCode,
      ),
    );
  }

  void _showNfcToolsSheet(
    BuildContext context, {
    required String currencyCode,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MomoNfcSheet(currencyCode: currencyCode),
    );
  }

  void _showSendMoneySheet(
    BuildContext context, {
    required CoolCountry country,
    required String momoNumber,
    String? momoCode,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MomoSendMoneySheet(
        country: country,
        momoNumber: momoNumber,
        momoCode: momoCode,
      ),
    );
  }
}
