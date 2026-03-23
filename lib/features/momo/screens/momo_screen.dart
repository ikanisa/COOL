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
import '../widgets/momo_qr_nfc_widgets.dart';
import '../widgets/momo_send_sheet.dart';
import '../widgets/momo_sms_sync_status_card.dart';

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

    CoolToast.error(context, 'Add MoMo number first');
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final radii = context.coolRadii;
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
                        const SizedBox(height: 24),
                        BalanceCard(
                          amount: walletBalance,
                          currency: 'RWF',
                          changeAmount: walletInflows - walletOutflows,
                          subtitle:
                              'Protected wallet surface for statements, payouts, and receive setup.',
                          metrics: [
                            BalanceCardMetric(
                              label: 'Inflow',
                              value:
                                  '${_formatCompactAmount(walletInflows)} RWF',
                              accentColor: colors.success,
                            ),
                            BalanceCardMetric(
                              label: 'Outflow',
                              value:
                                  '${_formatCompactAmount(walletOutflows)} RWF',
                              accentColor: colors.warning,
                            ),
                            BalanceCardMetric(
                              label: 'Savings',
                              value:
                                  '${_formatCompactAmount(savingsTotal)} RWF',
                              accentColor: colors.info,
                            ),
                          ],
                          actions: [
                            BalanceCardAction(
                              label: l10n.sendMoney,
                              icon: Icons.send_rounded,
                              isPrimary: true,
                              onTap: () {
                                _showSendMoneySheet(
                                  context,
                                  country: country,
                                  momoNumber: momoNumber,
                                  momoCode: momoCode,
                                );
                              },
                            ),
                            BalanceCardAction(
                              label: l10n.statements,
                              icon: Icons.receipt_long_rounded,
                              onTap: () =>
                                  context.push(AppRoutes.momoStatements),
                            ),
                            BalanceCardAction(
                              label: l10n.momoQr,
                              icon: Icons.qr_code_2_rounded,
                              onTap: () {
                                if (!_ensureReceiveRouteConfigured()) {
                                  return;
                                }
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
                          ],
                        ),
                        const SizedBox(height: 24),
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
                          CoolCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: colors.info.withValues(
                                          alpha: 0.14,
                                        ),
                                        borderRadius: const BorderRadius.all(
                                          Radius.circular(CoolRadii.lg),
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.face_retouching_natural_rounded,
                                        color: colors.info,
                                      ),
                                    ),
                                    SizedBox(width: space.x3),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'BioPay',
                                            style: theme.textTheme.titleLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w900,
                                                  color: colors.primaryText,
                                                ),
                                          ),
                                          SizedBox(height: space.x1),
                                          Text(
                                            'Face-to-USSD handoff with your signed-in profile and wallet route. No phone OTP.',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: colors.secondaryText,
                                                  fontWeight: FontWeight.w500,
                                                  height: 1.4,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: space.x4),
                                CoolButton(
                                  label: 'Open BioPay',
                                  icon: Icons.arrow_outward_rounded,
                                  onTap: () =>
                                      context.push(AppRoutes.biopayHome),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: space.x5),
                        ],
                        CoolCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Trust and controls',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: colors.primaryText,
                                ),
                              ),
                              SizedBox(height: space.x2),
                              Text(
                                'Keep payment actions, receive channels, and record review separate and easy to scan.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w500,
                                  color: colors.secondaryText,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: const [
                                  _WalletTrustChip(
                                    icon: Icons.verified_user_outlined,
                                    label: 'Protected sessions',
                                  ),
                                  _WalletTrustChip(
                                    icon: Icons.rule_folder_outlined,
                                    label: 'Compliant records',
                                  ),
                                  _WalletTrustChip(
                                    icon: Icons.account_balance_outlined,
                                    label: 'Authoritative ledger',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              MomoActionGrid(
                                onOpenStatements: () =>
                                    context.push(AppRoutes.momoStatements),
                                onScanQr: _scanQrCode,
                                onOpenQrCode: () {
                                  if (!_ensureReceiveRouteConfigured()) {
                                    return;
                                  }
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
                                  if (!_ensureReceiveRouteConfigured()) {
                                    return;
                                  }
                                  unawaited(
                                    Navigator.of(context).push<void>(
                                      MaterialPageRoute<void>(
                                        builder: (_) => const MomoNfcScreen(),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: space.x5),
                        CoolCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.sendMoneyTitle,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: colors.primaryText,
                                ),
                              ),
                              SizedBox(height: space.x2),
                              Text(
                                l10n.sendMoneyHint,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w500,
                                  color: colors.secondaryText,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 16),
                              CoolButton(
                                label: l10n.sendMoney,
                                icon: Icons.send_rounded,
                                onTap: () {
                                  _showSendMoneySheet(
                                    context,
                                    country: country,
                                    momoNumber: momoNumber,
                                    momoCode: momoCode,
                                  );
                                },
                              ),
                            ],
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
                        color: colors.elevatedBackground,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(CoolRadii.md),
                        ),
                        border: Border.all(color: colors.border),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CupertinoActivityIndicator(radius: 9),
                          ),
                          SizedBox(width: space.x3),
                          Expanded(
                            child: Text(
                              l10n.momoNfcLaunchingOverlay,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colors.primaryText,
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
}

class _WalletTrustChip extends StatelessWidget {
  const _WalletTrustChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: space.x3, vertical: space.x2),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong,
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.pill)),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.secondaryText),
          SizedBox(width: space.x1),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

int _walletBalance(MomoStatementBundle? bundle) {
  if (bundle == null) {
    return 0;
  }
  var total = 0;
  for (final entry in bundle.walletEntries) {
    total += entry.isCredit ? entry.amount : -entry.amount;
  }
  return total;
}

int _walletInflows(MomoStatementBundle? bundle) {
  if (bundle == null) {
    return 0;
  }
  return bundle.walletEntries
      .where((entry) => entry.isCredit)
      .fold<int>(0, (sum, entry) => sum + entry.amount);
}

int _walletOutflows(MomoStatementBundle? bundle) {
  if (bundle == null) {
    return 0;
  }
  return bundle.walletEntries
      .where((entry) => entry.isDebit)
      .fold<int>(0, (sum, entry) => sum + entry.amount);
}

int _savingsTotal(MomoStatementBundle? bundle) {
  if (bundle == null) {
    return 0;
  }
  return bundle.savingsEntries
      .where((entry) => entry.isConfirmed)
      .fold<int>(0, (sum, entry) => sum + entry.amount);
}

String _formatCompactAmount(int amount) {
  if (amount >= 1000000) {
    return '${(amount / 1000000).toStringAsFixed(amount % 1000000 == 0 ? 0 : 1)}M';
  }
  if (amount >= 1000) {
    return '${(amount / 1000).toStringAsFixed(amount % 1000 == 0 ? 0 : 1)}K';
  }
  return '$amount';
}
