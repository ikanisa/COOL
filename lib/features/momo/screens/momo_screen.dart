import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_market.dart';
import '../../../core/config/country_catalog.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/models/momo_qr_payload.dart';
import '../../../core/providers/engagement_providers.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/balance_card.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/secure_screen_mixin.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../auth/providers/auth_provider.dart';
import '../../profile/widgets/profile_app_access_sheet.dart';
import '../models/momo_statement.dart';
import '../providers/momo_statement_providers.dart';
import '../providers/momo_service_provider.dart';
import '../screens/momo_nfc_screen.dart';
import '../services/nfc_service.dart';

import '../widgets/momo_cards_widgets.dart';
import '../widgets/momo_qr_widgets.dart';
import '../widgets/momo_send_sheet.dart';
import '../widgets/momo_sms_sync_status_card.dart';

part 'momo_screen_parts.dart';

/// Mobile Money hub — USSD gateway, QR code, and NFC transfers.
class MomoScreen extends ConsumerStatefulWidget {
  const MomoScreen({this.launchUri, super.key});

  final Uri? launchUri;

  @override
  ConsumerState<MomoScreen> createState() => _MomoScreenState();
}

class _MomoScreenState extends ConsumerState<MomoScreen>
    with SecureScreenMixin<MomoScreen> {
  bool _launchingIncomingPayment = false;
  bool _handledIncomingPayment = false;

  // ─── Lifecycle ──────────────────────────────────────────────────────────

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

  // ─── Navigation ─────────────────────────────────────────────────────────

  void _closeOrReturnHome() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(AppRoutes.home);
  }

  // ─── Incoming payment handling ──────────────────────────────────────────

  Future<void> _maybeHandleIncomingPayment() async {
    if (_handledIncomingPayment) return;

    final nfcPayload = widget.launchUri == null
        ? null
        : NfcPaymentPayload.tryParseUri(widget.launchUri!);
    final qrPayload = widget.launchUri == null
        ? null
        : MomoQrPayload.tryParseUri(widget.launchUri!);
    if (nfcPayload == null && qrPayload == null) return;

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

    if (qrPayload == null || !mounted) return;

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
      if (!mounted) return;
      CoolToast.success(context, context.l10n.momoLaunchingUssd);
    } catch (_) {
      if (!mounted) return;
      CoolToast.error(context, context.l10n.momoNfcLaunchFailed);
    } finally {
      if (mounted) setState(() => _launchingIncomingPayment = false);
    }
  }

  // ─── Helpers ────────────────────────────────────────────────────────────

  String get _currentMomoNumber {
    final user = ref.read(authProvider).user;
    if (user?.momoNumber.isNotEmpty == true) return user!.momoNumber;
    if (user?.phone.isNotEmpty == true) return user!.phone;
    return '';
  }

  String? get _currentMomoCode => ref.read(authProvider).user?.momoCode;

  bool get _hasReceiveRouteConfigured =>
      _currentMomoNumber.trim().isNotEmpty ||
      (_currentMomoCode?.trim().isNotEmpty ?? false);

  bool _ensureReceiveRouteConfigured() {
    if (_hasReceiveRouteConfigured) return true;
    CoolToast.error(context, 'Add MoMo number first');
    return false;
  }

  CoolCountry _resolvePayloadCountry(MomoQrPayload _) => AppMarket.country;

  Future<void> _scanQrCode() async {
    final payload = await context.push<MomoQrPayload>(
      '${AppRoutes.scanner}?mode=momo',
    );
    if (!mounted || payload == null) return;
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

  void _showSendMoneySheet(
    BuildContext context, {
    required CoolCountry country,
    required String momoNumber,
    String? momoCode,
    String? initialRecipient,
    String? initialAmount,
    MomoRecipientType initialRecipientType = MomoRecipientType.phoneNumber,
  }) {
    showCoolBottomSheet<void>(
      context: context,
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

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final biopayEnabled = ref.watch(
      featureFlagsStateProvider.select(
        (flags) => flags.isBiopayEnabled(isAdmin: user?.isAdmin ?? false),
      ),
    );
    final country = AppMarket.country;
    final momoNumber = user?.momoNumber.isNotEmpty == true
        ? user!.momoNumber
        : user?.phone.isNotEmpty == true
        ? user!.phone
        : '';
    final momoCode = user?.momoCode;
    final statementBundle = ref
        .watch(momoStatementBundleProvider(const MomoStatementQuery()))
        .valueOrNull;
    final walletBalance = _walletBalance(statementBundle);
    final walletInflows = _walletInflows(statementBundle);
    final walletOutflows = _walletOutflows(statementBundle);
    final savingsTotal = _savingsTotal(statementBundle);

    return CoolScreenBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: Semantics(
            button: true,
            label: MaterialLocalizations.of(context).backButtonTooltip,
            hint: 'Go back',
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
                    padding: EdgeInsets.fromLTRB(
                      space.x5,
                      space.x5,
                      space.x5,
                      96,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        Text(
                          l10n.momoScreenTitle,
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: colors.primaryText,
                          ),
                        ),
                        const SizedBox(height: CoolSpace.x6),
                        _buildBalanceSection(
                          context: context,
                          colors: colors,
                          theme: theme,
                          walletBalance: walletBalance,
                          walletInflows: walletInflows,
                          walletOutflows: walletOutflows,
                          savingsTotal: savingsTotal,
                          country: country,
                          momoNumber: momoNumber,
                          momoCode: momoCode,
                          onSendMoney: () => _showSendMoneySheet(
                            context,
                            country: country,
                            momoNumber: momoNumber,
                            momoCode: momoCode,
                          ),
                          onOpenStatements: () =>
                              context.push(AppRoutes.momoStatements),
                          onOpenQrCode: () {
                            if (!_ensureReceiveRouteConfigured()) return;
                            unawaited(
                              Navigator.of(context).push<void>(
                                MaterialPageRoute<void>(
                                  builder: (_) => MomoReceiveQrScreen(
                                    country: country,
                                    momoNumber: momoNumber,
                                    momoCode: momoCode,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: CoolSpace.x6),
                        MomoSmsSyncStatusCard(
                          onManageAccess: () =>
                              ProfileAppAccessSheet.show(context),
                          onOpenStatements: () =>
                              context.push(AppRoutes.momoStatements),
                          onSyncComplete: (_) {
                            ref.invalidate(
                              momoStatementBundleProvider(
                                const MomoStatementQuery(),
                              ),
                            );
                          },
                        ),
                        SizedBox(height: space.x5),
                        if (biopayEnabled) ...[
                          _buildBiopayCard(
                            context: context,
                            colors: colors,
                            space: space,
                            theme: theme,
                            onOpen: () =>
                                context.push(AppRoutes.biopayHome),
                          ),
                          SizedBox(height: space.x5),
                        ],
                        _buildTrustAndActionsCard(
                          context: context,
                          colors: colors,
                          space: space,
                          theme: theme,
                          onOpenStatements: () =>
                              context.push(AppRoutes.momoStatements),
                          onScanQr: _scanQrCode,
                          onOpenQrCode: () {
                            if (!_ensureReceiveRouteConfigured()) return;
                            unawaited(
                              Navigator.of(context).push<void>(
                                MaterialPageRoute<void>(
                                  builder: (_) => MomoReceiveQrScreen(
                                    country: country,
                                    momoNumber: momoNumber,
                                    momoCode: momoCode,
                                  ),
                                ),
                              ),
                            );
                          },
                          onOpenNfcTools: () {
                            if (!_ensureReceiveRouteConfigured()) return;
                            unawaited(
                              Navigator.of(context).push<void>(
                                MaterialPageRoute<void>(
                                  builder: (_) => const MomoNfcScreen(),
                                ),
                              ),
                            );
                          },
                        ),
                        SizedBox(height: space.x5),
                        _buildSendMoneyCard(
                          context: context,
                          colors: colors,
                          space: space,
                          theme: theme,
                          onSend: () => _showSendMoneySheet(
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
              _buildLaunchingOverlay(
                context: context,
                colors: colors,
                space: space,
                theme: theme,
              ),
          ],
        ),
      ),
    );
  }
}