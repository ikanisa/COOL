import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/app_market.dart';
import '../../../core/config/country_catalog.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/models/momo_qr_payload.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_palette.dart';

import '../../../core/providers/app_access_provider.dart';
import '../../../core/providers/app_lifecycle_providers.dart';
import '../../../core/services/app_access_service.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/secure_screen_mixin.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/momo_service_provider.dart';
import '../screens/momo_nfc_screen.dart';
import '../services/momo_sms_autoread_service.dart';
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

    return Scaffold(
      backgroundColor: palette.bg,
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
                      _SmsSyncCta(
                        onSyncComplete: () {
                          if (mounted) {
                            CoolToast.success(
                              context,
                              'M-Money SMS synced!',
                            );
                          }
                        },
                      ),
                      CoolCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Money tools',
                              style: GoogleFonts.dmSans(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: palette.text,
                              ),
                            ),
                            const SizedBox(height: 12),
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
}

/// Shows a CTA card when SMS sync is not enabled, guiding users to enable it.
class _SmsSyncCta extends ConsumerStatefulWidget {
  const _SmsSyncCta({this.onSyncComplete});

  final VoidCallback? onSyncComplete;

  @override
  ConsumerState<_SmsSyncCta> createState() => _SmsSyncCtaState();
}

class _SmsSyncCtaState extends ConsumerState<_SmsSyncCta> {
  bool _syncing = false;
  bool _smsEnabled = false;

  @override
  void initState() {
    super.initState();
    _checkSmsStatus();
  }

  Future<void> _checkSmsStatus() async {
    final enabled = await ref.read(appAccessServiceProvider).isEnabled(
      AppAccessPermission.sms,
    );
    if (mounted) {
      setState(() => _smsEnabled = enabled);
    }
  }

  Future<void> _enableAndSync() async {
    if (_syncing) return;
    setState(() => _syncing = true);

    try {
      // 1. Enable SMS in app settings
      await ref.read(appAccessServiceProvider).enableAndRequest(
        AppAccessPermission.sms,
      );

      // 2. Refresh the autoread service (triggers permission + listener + sync)
      final service = ref.read(momoSmsAutoreadServiceProvider);
      await service.refresh(forcePermissionRequest: true);

      // 3. Trigger manual inbox sync
      try {
        await service.syncInbox(trigger: MomoInboxSyncTrigger.manual);
      } catch (_) {
        // syncInbox may throw if already ran via initial sync — that's OK
      }

      if (mounted) {
        setState(() => _smsEnabled = true);
        widget.onSyncComplete?.call();
      }
    } catch (error) {
      if (mounted) {
        CoolToast.error(context, 'SMS sync failed. Try again in Settings.');
      }
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_smsEnabled) return const SizedBox.shrink();

    final palette = context.coolPalette;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: CoolCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sms_rounded, color: palette.accent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Sync M-Money SMS',
                    style: GoogleFonts.dmSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: palette.text,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Import past year M-Money confirmations to auto-track payments, '
              'contributions, and transactions.',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: palette.text3,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _syncing ? null : _enableAndSync,
                icon: _syncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.sync_rounded, size: 18),
                label: Text(_syncing ? 'Syncing…' : 'Enable & Sync'),
                style: FilledButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
