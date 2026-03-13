import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/app_market.dart';
import '../../../core/config/country_catalog.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/models/momo_qr_payload.dart';
import '../../../core/providers/app_access_provider.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/momo_service_provider.dart';
import '../services/nfc_service.dart';
import '../widgets/momo_cards_widgets.dart';
import '../widgets/momo_qr_nfc_widgets.dart';
import '../widgets/momo_send_sheet.dart';

/// Mobile Money hub — USSD gateway, QR code, and NFC transfers.
class MomoScreen extends ConsumerStatefulWidget {
  const MomoScreen({this.launchUri, super.key});

  final Uri? launchUri;

  @override
  ConsumerState<MomoScreen> createState() => _MomoScreenState();
}

class _MomoScreenState extends ConsumerState<MomoScreen> {
  bool _launchingIncomingPayment = false;
  bool _handledIncomingPayment = false;

  void _closeOrReturnHome() {
    if (context.canPop()) {
      context.pop();
      return;
    }

    context.go(AppRoutes.home);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeHandleIncomingPayment();
    });
  }

  @override
  void didUpdateWidget(covariant MomoScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.launchUri?.toString() != widget.launchUri?.toString()) {
      _handledIncomingPayment = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeHandleIncomingPayment();
      });
    }
  }

  Future<void> _maybeHandleIncomingPayment() async {
    if (_handledIncomingPayment) {
      return;
    }

    final nfcPayload = widget.launchUri == null
        ? null
        : NfcPaymentPayload.tryParseUri(widget.launchUri!);
    final qrPayload = widget.launchUri == null
        ? null
        : MomoQrPayload.tryParseUri(widget.launchUri!);
    if (nfcPayload == null && qrPayload == null) {
      return;
    }

    _handledIncomingPayment = true;
    if (nfcPayload != null) {
      final amount = int.tryParse(
        nfcPayload.amount.replaceAll(RegExp(r'[^0-9]'), ''),
      );
      if (amount == null || amount <= 0) {
        if (mounted) {
          CoolToast.error(context, context.l10n.momoNfcInvalidRequest);
        }
        return;
      }

      await _launchIncomingPayment(
        recipientMomo: nfcPayload.recipientValue,
        amount: amount,
        reference: 'NFC-${DateTime.now().millisecondsSinceEpoch}',
        recipientType: nfcPayload.recipientType,
      );
      return;
    }

    if (qrPayload == null || !mounted) {
      return;
    }

    if (qrPayload.canLaunchImmediately) {
      await _launchIncomingPayment(
        recipientMomo: qrPayload.recipientValue,
        amount: qrPayload.amount!,
        reference:
            qrPayload.reference ??
            'QR-${DateTime.now().millisecondsSinceEpoch}',
        recipientType: qrPayload.recipientType,
      );
      return;
    }

    _showSendMoneySheet(
      context,
      country: _resolvePayloadCountry(qrPayload),
      momoNumber: _currentMomoNumber,
      momoCode: _currentMomoCode,
      initialRecipient: qrPayload.recipientValue,
      initialAmount: qrPayload.amount?.toString(),
      initialRecipientType: qrPayload.recipientType,
    );
  }

  Future<void> _launchIncomingPayment({
    required String recipientMomo,
    required int amount,
    required String reference,
    required MomoRecipientType recipientType,
  }) async {
    setState(() => _launchingIncomingPayment = true);
    try {
      await ref
          .read(momoServiceProvider)
          .initiatePayment(
            recipientMomo: recipientMomo,
            amount: amount,
            reference: reference,
            recipientType: recipientType,
            countryCode: AppMarket.countryCode,
          );
      if (!mounted) {
        return;
      }
      CoolToast.success(context, context.l10n.momoLaunchingUssd);
    } catch (_) {
      if (!mounted) {
        return;
      }
      CoolToast.error(context, context.l10n.momoNfcLaunchFailed);
    } finally {
      if (mounted) {
        setState(() => _launchingIncomingPayment = false);
      }
    }
  }

  CoolCountry get _currentCountry => AppMarket.country;

  String get _currentMomoNumber {
    final user = ref.read(authProvider).user;
    if (user?.momoNumber.isNotEmpty == true) {
      return user!.momoNumber;
    }
    if (user?.phone.isNotEmpty == true) {
      return user!.phone;
    }
    return _currentCountry.buildE164Phone('91234567');
  }

  String? get _currentMomoCode => ref.read(authProvider).user?.momoCode;

  CoolCountry _resolvePayloadCountry(MomoQrPayload _) => AppMarket.country;

  Future<void> _scanQrCode() async {
    final payload = await context.push<MomoQrPayload>(
      '${AppRoutes.scanner}?mode=momo',
    );
    if (!mounted || payload == null) {
      return;
    }

    _showSendMoneySheet(
      context,
      country: _resolvePayloadCountry(payload),
      momoNumber: _currentMomoNumber,
      momoCode: _currentMomoCode,
      initialRecipient: payload.recipientValue,
      initialAmount: payload.amount?.toString(),
      initialRecipientType: payload.recipientType,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final country = AppMarket.country;
    final momoNumber = user?.momoNumber.isNotEmpty == true
        ? user!.momoNumber
        : user?.phone.isNotEmpty == true
        ? user!.phone
        : country.buildE164Phone('91234567');
    final momoCode = user?.momoCode;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: Semantics(
          button: true,
          label: MaterialLocalizations.of(context).backButtonTooltip,
          hint: 'Returns to the previous screen',
          child: IconButton(
            onPressed: _closeOrReturnHome,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        title: Text(
          l10n.momoScreenTitle,
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        actions: [
          Semantics(
            button: true,
            label: l10n.navHome,
            hint: 'Opens the home screen',
            child: IconButton(
              onPressed: () => context.go(AppRoutes.home),
              tooltip: l10n.navHome,
              icon: const Icon(Icons.home_rounded),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          CoolScreenBackground(
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
                        country: country,
                        momoNumber: momoNumber,
                        onOpenStatements: () =>
                            context.push(AppRoutes.momoStatements),
                        onOpenQrCode: () => _showQrCodeSheet(
                          context,
                          country: country,
                          momoNumber: momoNumber,
                          momoCode: momoCode,
                        ),
                        onRequestPayment: () => _showRequestPaymentSheet(
                          context,
                          country: country,
                          momoNumber: momoNumber,
                          momoCode: momoCode,
                        ),
                        onScanQr: _scanQrCode,
                        onOpenNfcTools: () => _showNfcToolsSheet(
                          context,
                          country: country,
                          momoNumber: momoNumber,
                          momoCode: momoCode,
                        ),
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          if (_launchingIncomingPayment)
            Positioned(
              left: 18,
              right: 18,
              top: 12,
              child: Semantics(
                liveRegion: true,
                label: l10n.momoNfcLaunchingOverlay,
                child: ExcludeSemantics(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CupertinoActivityIndicator(radius: 9),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l10n.momoNfcLaunchingOverlay,
                            style: GoogleFonts.dmSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
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
    required CoolCountry country,
    required String momoNumber,
    String? momoCode,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MomoNfcSheet(
        country: country,
        momoNumber: momoNumber,
        momoCode: momoCode,
        appAccessService: ref.read(appAccessServiceProvider),
        momoService: ref.read(momoServiceProvider),
      ),
    );
  }

  void _showSendMoneySheet(
    BuildContext context, {
    required CoolCountry country,
    required String momoNumber,
    String? momoCode,
    String? initialRecipient,
    String? initialAmount,
    MomoRecipientType initialRecipientType = MomoRecipientType.phoneNumber,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MomoSendMoneySheet(
        country: country,
        momoNumber: momoNumber,
        momoService: ref.read(momoServiceProvider),
        momoCode: momoCode,
        initialRecipient: initialRecipient,
        initialAmount: initialAmount,
        initialRecipientType: initialRecipientType,
      ),
    );
  }

  void _showRequestPaymentSheet(
    BuildContext context, {
    required CoolCountry country,
    required String momoNumber,
    String? momoCode,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MomoPaymentRequestSheet(
        country: country,
        momoNumber: momoNumber,
        momoCode: momoCode,
      ),
    );
  }
}
