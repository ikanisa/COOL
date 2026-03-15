import 'package:flutter/foundation.dart';
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
import '../../../core/providers/app_lifecycle_providers.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/momo_service_provider.dart';
import '../services/nfc_service.dart';
import '../services/momo_sms_autoread_service.dart';
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
  bool _syncingSmsInbox = false;
  bool _showMoreTools = false;

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

  String get _currentMomoNumber {
    final user = ref.read(authProvider).user;
    if (user?.momoNumber.isNotEmpty == true) {
      return user!.momoNumber;
    }
    if (user?.phone.isNotEmpty == true) {
      return user!.phone;
    }
    return '';
  }

  String? get _currentMomoCode => ref.read(authProvider).user?.momoCode;

  bool get _hasReceiveRouteConfigured =>
      _currentMomoNumber.trim().isNotEmpty ||
      (_currentMomoCode?.trim().isNotEmpty ?? false);

  bool _ensureReceiveRouteConfigured() {
    if (_hasReceiveRouteConfigured) {
      return true;
    }

    CoolToast.error(
      context,
      'Add your Rwanda MoMo number in profile first to generate a receive QR.',
    );
    return false;
  }

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

  Future<void> _syncSmsInbox() async {
    if (_syncingSmsInbox) {
      return;
    }

    setState(() => _syncingSmsInbox = true);
    try {
      final result = await ref
          .read(momoSmsAutoreadServiceProvider)
          .syncInbox(trigger: MomoInboxSyncTrigger.manual);
      if (!mounted) {
        return;
      }
      if (result.uploadedMessages > 0) {
        CoolToast.success(
          context,
          'Synced ${result.uploadedMessages} new M-Money SMS from the inbox.',
        );
      } else {
        CoolToast.info(
          context,
          'Inbox checked. No new M-Money SMS needed syncing.',
        );
      }
    } on MomoSmsSyncException catch (error) {
      if (!mounted) {
        return;
      }
      CoolToast.error(context, error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      CoolToast.error(context, 'Could not sync the M-Money inbox right now.');
    } finally {
      if (mounted) {
        setState(() => _syncingSmsInbox = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.coolPalette;
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final country = AppMarket.country;
    final momoNumber = user?.momoNumber.isNotEmpty == true
        ? user!.momoNumber
        : user?.phone.isNotEmpty == true
        ? user!.phone
        : '';
    final momoCode = user?.momoCode;
    final hasReceiveRoute =
        momoNumber.trim().isNotEmpty || (momoCode?.trim().isNotEmpty ?? false);
    final isAndroidSmsAvailable =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    return Scaffold(
      backgroundColor: palette.bg,
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
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      Text(
                        l10n.momoScreenTitle,
                        style: GoogleFonts.dmSans(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: palette.text,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (hasReceiveRoute)
                        MomoQrCodeCard(
                          country: country,
                          momoNumber: momoNumber,
                          momoCode: momoCode,
                        )
                      else
                        CoolCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Receive by QR',
                                style: GoogleFonts.dmSans(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: palette.text,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Add your Rwanda MoMo number in profile. Then COOL can generate your receive QR and payment requests using the local 07 format.',
                                style: GoogleFonts.dmSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: palette.text2,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 16),
                              CoolButton(
                                label: 'Open profile',
                                onTap: () => context.go(AppRoutes.profile),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
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
                      const MomoPaymentSafetyCard(),
                      const SizedBox(height: 16),
                      CoolCard(
                        onTap: () {
                          setState(() {
                            _showMoreTools = !_showMoreTools;
                          });
                        },
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Extra Tools',
                                    style: GoogleFonts.dmSans(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: palette.text,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _showMoreTools
                                        ? 'Hide SMS sync and QR/NFC tools.'
                                        : 'Open SMS sync, QR/NFC, and statements.',
                                    style: GoogleFonts.dmSans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      color: palette.text2,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              _showMoreTools
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: palette.text2,
                            ),
                          ],
                        ),
                      ),
                      if (_showMoreTools) ...[
                        const SizedBox(height: 16),
                        MomoInboxSyncCard(
                          isAndroidSmsAvailable: isAndroidSmsAvailable,
                          isSyncing: _syncingSmsInbox,
                          onSyncTap: _syncSmsInbox,
                        ),
                        const SizedBox(height: 16),
                        MomoToolsCard(
                          country: country,
                          momoNumber: momoNumber,
                          onOpenStatements: () =>
                              context.push(AppRoutes.momoStatements),
                          onOpenQrCode: () {
                            if (!_ensureReceiveRouteConfigured()) {
                              return;
                            }
                            _showQrCodeSheet(
                              context,
                              country: country,
                              momoNumber: momoNumber,
                              momoCode: momoCode,
                            );
                          },
                          onRequestPayment: () {
                            if (!_ensureReceiveRouteConfigured()) {
                              return;
                            }
                            _showRequestPaymentSheet(
                              context,
                              country: country,
                              momoNumber: momoNumber,
                              momoCode: momoCode,
                            );
                          },
                          onScanQr: _scanQrCode,
                          onOpenNfcTools: () {
                            if (!_ensureReceiveRouteConfigured()) {
                              return;
                            }
                            _showNfcToolsSheet(
                              context,
                              country: country,
                              momoNumber: momoNumber,
                              momoCode: momoCode,
                            );
                          },
                        ),
                      ],
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
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: palette.border),
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
                              color: palette.text,
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
