import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/services/app_access_service.dart';
import '../../../core/services/momo_service.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../core/utils/phone_validator.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_text_field.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../services/nfc_hce_service.dart';
import '../services/nfc_service.dart';
import 'momo_send_sheet.dart';
import '../../../core/l10n/l10n.dart';

// ═════════════════════════════════════════════════════════════════════════════
// NFC BOTTOM SHEET
// ═════════════════════════════════════════════════════════════════════════════

class MomoNfcSheet extends StatelessWidget {
  const MomoNfcSheet({
    required this.country,
    required this.momoNumber,
    required this.momoService,
    required this.appAccessService,
    this.momoCode,
    super.key,
  });

  final CoolCountry country;
  final String momoNumber;
  final MomoService momoService;
  final AppAccessService appAccessService;
  final String? momoCode;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'NFC pay',
                      style: GoogleFonts.dmSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: palette.text,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: context.l10n.close,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              MomoNfcCard(
                country: country,
                momoNumber: momoNumber,
                momoCode: momoCode,
                momoService: momoService,
                appAccessService: appAccessService,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// NFC CARD (read / write)
// ═════════════════════════════════════════════════════════════════════════════

class MomoNfcCard extends StatefulWidget {
  const MomoNfcCard({
    required this.country,
    required this.momoNumber,
    required this.momoService,
    required this.appAccessService,
    this.momoCode,
    super.key,
  });

  final CoolCountry country;
  final String momoNumber;
  final MomoService momoService;
  final AppAccessService appAccessService;
  final String? momoCode;

  @override
  State<MomoNfcCard> createState() => _MomoNfcCardState();
}

class _MomoNfcCardState extends State<MomoNfcCard>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final AppAccessService _appAccessService = widget.appAccessService;
  final _nfcHceService = NfcHceService.instance;
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();
  late final TextEditingController _nfcMomoNumberController;
  late final TextEditingController _nfcMomoCodeController;
  final _nfcAmountController = TextEditingController();
  late MomoRecipientType _nfcRecipientType;
  bool _isScanning = false;
  bool _isActivating = false;
  bool _isReceiveModeActive = false;
  bool _supportsPhoneTap = false;
  AppAccessSnapshot? _nfcAccess;
  NfcPaymentPayload? _activePayload;
  bool _refreshOnResume = false;

  bool get _nfcHasNumber => _nfcMomoNumberController.text.trim().isNotEmpty;
  bool get _nfcHasCode => _nfcMomoCodeController.text.trim().isNotEmpty;

  String get _nfcActiveRecipientValue => switch (_nfcRecipientType) {
    MomoRecipientType.phoneNumber => _nfcMomoNumberController.text.trim(),
    MomoRecipientType.code => _nfcMomoCodeController.text.trim(),
  };

  @override
  void initState() {
    super.initState();
    _nfcMomoNumberController = TextEditingController(text: widget.momoNumber);
    _nfcMomoCodeController = TextEditingController(
      text: widget.momoCode ?? '',
    );
    _nfcRecipientType = widget.momoNumber.trim().isNotEmpty
        ? MomoRecipientType.phoneNumber
        : MomoRecipientType.code;
    WidgetsBinding.instance.addObserver(this);
    _appAccessService.changes.addListener(_handleAccessServiceChange);
    _refreshNfcAccess();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _nfcMomoNumberController.dispose();
    _nfcMomoCodeController.dispose();
    _nfcAmountController.dispose();
    _appAccessService.changes.removeListener(_handleAccessServiceChange);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_refreshOnResume) {
      return;
    }
    _refreshOnResume = false;
    _refreshNfcAccess();
  }

  void _handleAccessServiceChange() {
    if (!mounted) {
      return;
    }
    _refreshNfcAccess();
  }

  Future<void> _refreshNfcAccess() async {
    final snapshot = await _appAccessService.getSnapshot(
      AppAccessPermission.nfc,
    );
    final supportsPhoneTap = await _nfcHceService.isSupported();
    final isReceiveModeActive = supportsPhoneTap
        ? await _nfcHceService.isPaymentRequestActive()
        : false;
    final activeUri = supportsPhoneTap && isReceiveModeActive
        ? await _nfcHceService.getPaymentRequestUri()
        : null;
    if (mounted) {
      setState(() {
        _nfcAccess = snapshot;
        _supportsPhoneTap = supportsPhoneTap;
        _isReceiveModeActive = isReceiveModeActive;
        _activePayload = activeUri == null
            ? null
            : NfcPaymentPayload.tryParseUri(activeUri);
      });
    }
  }

  Future<void> _enableNfcAccess() async {
    final snapshot = await _appAccessService.enableAndRequest(
      AppAccessPermission.nfc,
    );
    if (!mounted) {
      return;
    }
    setState(() => _nfcAccess = snapshot);
  }

  Future<void> _openNfcSettings() async {
    _refreshOnResume = true;
    final opened = await _appAccessService.openSystemSettings(
      AppAccessPermission.nfc,
    );
    if (!mounted) {
      return;
    }
    if (!opened) {
      _refreshOnResume = false;
    }
    if (!opened) {
      CoolToast.error(context, 'Open failed');
      return;
    }
  }

  Future<void> _startRead() async {
    if (_nfcAccess?.isReady != true) {
      return;
    }
    setState(() => _isScanning = true);
    try {
      final result = await NfcService.readTag();
      if (!mounted) return;
      setState(() => _isScanning = false);
      _showReadResult(result);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isScanning = false);
      CoolToast.error(context, 'Read failed');
    }
  }

  Future<void> _launchPaymentFromTag(NfcReadResult result) async {
    final amount = int.tryParse(
      (result.amount ?? '').replaceAll(RegExp(r'[^0-9]'), ''),
    );
    final recipient = result.recipientValue?.trim();
    if (recipient == null ||
        recipient.isEmpty ||
        amount == null ||
        amount <= 0) {
      CoolToast.error(context, 'NFC payload incomplete');
      return;
    }

    try {
      await widget.momoService.initiatePayment(
        recipientMomo: recipient,
        amount: amount,
        reference: 'NFC-${DateTime.now().millisecondsSinceEpoch}',
        recipientType: result.recipientType,
        countryCode: result.countryCode ?? widget.country.isoCode,
      );
      if (!mounted) {
        return;
      }
      CoolToast.success(context, 'USSD payment launched');
    } catch (error) {
      if (!mounted) {
        return;
      }
      CoolToast.error(context, 'USSD launch failed');
    }
  }

  void _showReadResult(NfcReadResult result) {
    final recipientLabel = result.recipientType == MomoRecipientType.code
        ? 'MoMo Code'
        : 'MoMo Number';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final palette = context.coolPalette;
        return Container(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.border2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Icon(
                Icons.check_circle_rounded,
                size: 36,
                color: palette.accent,
              ),
              const SizedBox(height: 12),
              Text(
                result.hasPaymentData ? 'Payment tag' : 'Tag read',
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: palette.text,
                ),
              ),
              const SizedBox(height: 12),
              if (result.hasPaymentData) ...[
                _nfcInfoRow(recipientLabel, result.recipientValue!),
                const SizedBox(height: 8),
                _nfcInfoRow(
                  'Amount',
                  '${result.amount} ${widget.country.currencyCode}',
                ),
              ] else if (result.rawText != null)
                _nfcInfoRow('Data', result.rawText!)
              else
                Text(
                  'No data found',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    color: palette.text2,
                  ),
                ),
              const SizedBox(height: 18),
              if (result.hasPaymentData)
                CoolButton(
                  label: 'Pay by USSD',
                  onTap: () async {
                    Navigator.pop(context);
                    await _launchPaymentFromTag(result);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _nfcInfoRow(String label, String value) {
    final palette = context.coolPalette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: palette.text2,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: GoogleFonts.dmMono(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: palette.accent,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showWriteSheet() {
    final amountCtrl = TextEditingController(
      text: _nfcAmountController.text.trim(),
    );
    final recipientValue = _nfcActiveRecipientValue;
    final recipientType = _nfcRecipientType;

    if (recipientValue.isEmpty) {
      CoolToast.error(context, 'Add MoMo number first');
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        var isWriting = false;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final palette = context.coolPalette;
            return Container(
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              padding: EdgeInsets.fromLTRB(
                22,
                16,
                22,
                22 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: palette.border2,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _supportsPhoneTap ? 'Tap receive' : 'Write tag',
                    style: GoogleFonts.dmSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: palette.text,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: palette.surface2,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: palette.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          recipientType == MomoRecipientType.code
                              ? 'Receiving to MoMo Code'
                              : 'Receiving to MoMo Number',
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: palette.text2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          recipientType == MomoRecipientType.code
                              ? recipientValue
                              : PhoneValidator.formatMomoDisplay(
                                  recipientValue,
                                  widget.country,
                                ),
                          style: GoogleFonts.dmMono(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: palette.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  CoolTextField(
                    label: 'Amount (${widget.country.currencyCode})',
                    hint: '5000',
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    prefixIcon: Icons.payments_rounded,
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 18),
                  CoolButton(
                    label: isWriting
                        ? (_supportsPhoneTap
                            ? 'Starting tap'
                            : 'Writing tag')
                        : (_supportsPhoneTap
                            ? 'Start tap'
                            : 'Write tag'),
                    isLoading: isWriting,
                    onTap: () {
                      final amount = amountCtrl.text.trim();
                      if (recipientValue.isEmpty || amount.isEmpty) {
                        CoolToast.error(
                          context,
                          'Add amount and MoMo',
                        );
                        return;
                      }
                      setSheetState(() => isWriting = true);
                      final payload = NfcPaymentPayload(
                        recipientValue: recipientValue,
                        amount: amount,
                        recipientType: recipientType,
                        countryCode: widget.country.isoCode,
                      );
                      final future = _supportsPhoneTap
                          ? _nfcHceService.startPaymentRequest(
                              uri: payload.toDeepLinkUri(),
                            )
                          : NfcService.writeTag(
                              recipientValue: recipientValue,
                              amount: amount,
                              recipientType: recipientType,
                              countryCode: widget.country.isoCode,
                            );
                      future
                          .then((_) async {
                            if (!mounted || !context.mounted) {
                              return;
                            }
                            Navigator.pop(context);
                            await _refreshNfcAccess();
                            if (!mounted) {
                              return;
                            }
                            CoolToast.success(
                              this.context,
                              _supportsPhoneTap
                                  ? 'Tap ready'
                                  : 'Tag ready',
                            );
                          })
                          .catchError((Object _) {
                            setSheetState(() => isWriting = false);
                            if (mounted) {
                              CoolToast.error(
                                this.context,
                                'Write failed',
                              );
                            }
                          });
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final showWrite = !kIsWeb && Platform.isAndroid;
    final nfcAccess = _nfcAccess;
    final accessReady = nfcAccess?.isReady == true;
    final activePayload = _activePayload;
    final hasReceiveRoute = _nfcActiveRecipientValue.isNotEmpty;
    final isListening = _isScanning || _isReceiveModeActive;

    return CoolCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Compact NFC status header ───
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: (isListening ? palette.accent : palette.blue)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    isListening
                        ? Icons.contactless_rounded
                        : Icons.nfc_rounded,
                    size: 24,
                    color: isListening ? palette.accent : palette.blue,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NFC Pay',
                        style: GoogleFonts.dmSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: palette.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        nfcAccess == null
                            ? 'Checking...'
                            : accessReady
                                ? (isListening ? 'Active' : 'Ready')
                                : switch (nfcAccess.kind) {
                                    AppAccessStateKind.disabledInApp =>
                                      'NFC off in app',
                                    AppAccessStateKind.serviceDisabled =>
                                      'NFC off',
                                    AppAccessStateKind.notAvailable =>
                                      'NFC unsupported',
                                    _ => 'Ready',
                                  },
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color:
                              isListening ? palette.accent : palette.text2,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isListening)
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: palette.accent,
                      boxShadow: [
                        BoxShadow(
                          color: palette.accent.withValues(alpha: 0.4),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),

            // ─── Enable NFC if needed ───
            if (nfcAccess != null && !accessReady) ...[
              CoolButton(
                label: nfcAccess.kind == AppAccessStateKind.disabledInApp
                    ? 'Enable NFC'
                    : 'Open NFC settings',
                icon: nfcAccess.kind == AppAccessStateKind.disabledInApp
                    ? Icons.nfc_rounded
                    : Icons.settings_rounded,
                onTap: nfcAccess.kind == AppAccessStateKind.disabledInApp
                    ? _enableNfcAccess
                    : _openNfcSettings,
              ),
            ] else if (accessReady) ...[
              // ─── MoMo route type chips ───
              if (_nfcHasCode && _nfcHasNumber) ...[
                Row(
                  children: [
                    Expanded(
                      child: MomoRouteTypeChip(
                        label: 'MoMo Number',
                        isActive: _nfcRecipientType ==
                            MomoRecipientType.phoneNumber,
                        onTap: () => setState(
                          () => _nfcRecipientType =
                              MomoRecipientType.phoneNumber,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MomoRouteTypeChip(
                        label: 'MoMo Code',
                        isActive:
                            _nfcRecipientType == MomoRecipientType.code,
                        onTap: () => setState(
                          () =>
                              _nfcRecipientType = MomoRecipientType.code,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],

              // ─── MoMo input ───
              if (_nfcRecipientType == MomoRecipientType.phoneNumber)
                CoolTextField(
                  label: 'MoMo Number',
                  hint: widget.country.phoneExampleHint(),
                  controller: _nfcMomoNumberController,
                  keyboardType: TextInputType.phone,
                  prefixIcon: Icons.phone_rounded,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                )
              else
                CoolTextField(
                  label: 'MoMo Code',
                  hint: widget.country.momoCodeExample ?? '123456',
                  controller: _nfcMomoCodeController,
                  keyboardType: TextInputType.number,
                  prefixIcon: Icons.tag_rounded,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                ),
              const SizedBox(height: 14),

              // ─── Amount ───
              CoolTextField(
                label: 'Amount (${widget.country.currencyCode})',
                hint: '5,000',
                controller: _nfcAmountController,
                keyboardType: TextInputType.number,
                prefixIcon: Icons.payments_rounded,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
              ),

              // ─── Active tap payload info ───
              if (_supportsPhoneTap &&
                  _isReceiveModeActive &&
                  activePayload != null) ...[
                const SizedBox(height: 14),
                _nfcInfoRow(
                  activePayload.recipientType == MomoRecipientType.code
                      ? 'MoMo Code'
                      : 'MoMo Number',
                  activePayload.recipientValue,
                ),
                const SizedBox(height: 8),
                _nfcInfoRow(
                  'Amount',
                  '${activePayload.amount} ${widget.country.currencyCode}',
                ),
              ],
              const SizedBox(height: 18),

              // ─── Action buttons ───
              Row(
                children: [
                  Expanded(
                    child: CoolButton(
                      label: _isScanning ? 'Scanning...' : 'Read tag',
                      icon: Icons.nfc_rounded,
                      variant: CoolButtonVariant.primary,
                      isLoading: _isScanning,
                      onTap: _startRead,
                    ),
                  ),
                  if (showWrite) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: CoolButton(
                        label: _isReceiveModeActive
                            ? 'Update'
                            : (_supportsPhoneTap
                                ? 'Tap receive'
                                : 'Write tag'),
                        icon: _supportsPhoneTap
                            ? Icons.contactless_rounded
                            : Icons.nfc_rounded,
                        variant: CoolButtonVariant.secondary,
                        onTap: hasReceiveRoute
                            ? _showWriteSheet
                            : () => CoolToast.info(
                                  context,
                                  'Add MoMo first',
                                ),
                      ),
                    ),
                  ],
                ],
              ),

              // ─── Stop receive ───
              if (_supportsPhoneTap && _isReceiveModeActive) ...[
                const SizedBox(height: 10),
                CoolButton(
                  label:
                      _isActivating ? 'Stopping...' : 'Stop receive',
                  variant: CoolButtonVariant.secondary,
                  isLoading: _isActivating,
                  icon: Icons.stop_circle_rounded,
                  onTap: () async {
                    setState(() => _isActivating = true);
                    try {
                      await _nfcHceService.stopPaymentRequest();
                      if (!mounted) return;
                      await _refreshNfcAccess();
                      if (!mounted) return;
                      CoolToast.success(this.context, 'Tap off');
                    } catch (_) {
                      if (!mounted) return;
                      CoolToast.error(this.context, 'Stop failed');
                    } finally {
                      if (mounted) {
                        setState(() => _isActivating = false);
                      }
                    }
                  },
                ),
              ],
            ] else ...[
              const Center(child: CupertinoActivityIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}