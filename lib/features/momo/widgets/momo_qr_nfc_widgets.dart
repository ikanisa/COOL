import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/services/contacts_service.dart';
import '../../../core/models/momo_qr_payload.dart';
import '../../../core/providers/app_access_provider.dart';
import '../../../core/services/app_access_service.dart';
import '../../../core/services/momo_service.dart';
import '../../../core/services/whatsapp_contact_service.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../core/utils/phone_validator.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/contact_picker_sheet.dart';
import '../../../shared/widgets/cool_text_field.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../services/nfc_hce_service.dart';
import '../services/nfc_service.dart';

// ═════════════════════════════════════════════════════════════════════════════
// QR CODE BOTTOM SHEET
// ═════════════════════════════════════════════════════════════════════════════

class MomoQrSheet extends StatelessWidget {
  const MomoQrSheet({
    required this.country,
    required this.momoNumber,
    this.momoCode,
    super.key,
  });

  final CoolCountry country;
  final String momoNumber;
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
                      'MOMO QR',
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
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              MomoQrCodeCard(
                country: country,
                momoNumber: momoNumber,
                momoCode: momoCode,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MomoReceiveQrScreen extends StatelessWidget {
  const MomoReceiveQrScreen({
    required this.country,
    required this.momoNumber,
    this.momoCode,
    super.key,
  });

  final CoolCountry country;
  final String momoNumber;
  final String? momoCode;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
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
          'MOMO QR',
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
              MomoQrCodeCard(
                country: country,
                momoNumber: momoNumber,
                momoCode: momoCode,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// QR CODE CARD
// ═════════════════════════════════════════════════════════════════════════════

class MomoQrCodeCard extends StatefulWidget {
  const MomoQrCodeCard({
    required this.country,
    required this.momoNumber,
    this.momoCode,
    super.key,
  });

  final CoolCountry country;
  final String momoNumber;
  final String? momoCode;

  @override
  State<MomoQrCodeCard> createState() => _MomoQrCodeCardState();
}

class _MomoQrCodeCardState extends State<MomoQrCodeCard> {
  late final TextEditingController _momoNumberController;
  late final TextEditingController _momoCodeController;
  late MomoRecipientType _recipientType;
  bool _qrGenerated = false;

  bool get _hasNumber => _momoNumberController.text.trim().isNotEmpty;
  bool get _hasCode => _momoCodeController.text.trim().isNotEmpty;

  String get _routeLabel =>
      _recipientType == MomoRecipientType.code ? 'MoMo Code' : 'MoMo Number';

  String get _activeRecipientRaw => switch (_recipientType) {
    MomoRecipientType.phoneNumber => _momoNumberController.text.trim(),
    MomoRecipientType.code => _momoCodeController.text.trim(),
  };

  String get _normalizedRecipientValue => switch (_recipientType) {
    MomoRecipientType.phoneNumber => widget.country.buildE164Phone(
      _momoNumberController.text.trim(),
    ),
    MomoRecipientType.code => widget.country.normalizeMerchantCode(
      _momoCodeController.text.trim(),
    ),
  };

  String get _displayRecipient => switch (_recipientType) {
    MomoRecipientType.phoneNumber => PhoneValidator.formatMomoDisplay(
      _momoNumberController.text.trim(),
      widget.country,
    ),
    MomoRecipientType.code => _momoCodeController.text.trim(),
  };

  bool get _canGenerate => _activeRecipientRaw.isNotEmpty;

  MomoQrPayload get _payload => MomoQrPayload.profile(
    recipientValue: _normalizedRecipientValue,
    recipientType: _recipientType,
    countryCode: widget.country.isoCode,
  );

  String get _qrData => _payload.toQrData(widget.country);

  @override
  void initState() {
    super.initState();
    _momoNumberController = TextEditingController(text: widget.momoNumber);
    _momoCodeController = TextEditingController(text: widget.momoCode ?? '');
    _recipientType = widget.momoNumber.trim().isNotEmpty
        ? MomoRecipientType.phoneNumber
        : MomoRecipientType.code;
  }

  @override
  void dispose() {
    _momoNumberController.dispose();
    _momoCodeController.dispose();
    super.dispose();
  }

  void _generateQr() {
    if (!_canGenerate) {
      CoolToast.error(context, 'Enter your MoMo number or code');
      return;
    }
    setState(() => _qrGenerated = true);
  }

  Future<void> _sharePayload() {
    final shareText =
        'Pay me on ${widget.country.name} MoMo using $_routeLabel $_displayRecipient.\n${_payload.toAppLinkUri()}';
    return SharePlus.instance.share(
      ShareParams(
        text: shareText,
        subject: 'My MoMo payment QR',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return CoolCard(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            // ─── Route type chips ───
            if (_hasCode && _hasNumber) ...[
              Row(
                children: [
                  Expanded(
                    child: _NfcRouteTypeChip(
                      label: 'MoMo Number',
                      isActive: _recipientType == MomoRecipientType.phoneNumber,
                      onTap: () {
                        setState(
                          () => _recipientType = MomoRecipientType.phoneNumber,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _NfcRouteTypeChip(
                      label: 'MoMo Code',
                      isActive: _recipientType == MomoRecipientType.code,
                      onTap: () {
                        setState(() => _recipientType = MomoRecipientType.code);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
            ],

            // ─── Editable MoMo number / code ───
            if (_recipientType == MomoRecipientType.phoneNumber)
              CoolTextField(
                label: 'MoMo Number',
                hint: widget.country.phoneExampleHint(),
                controller: _momoNumberController,
                keyboardType: TextInputType.phone,
                prefixIcon: Icons.phone_rounded,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() => _qrGenerated = false),
              )
            else
              CoolTextField(
                label: 'MoMo Code',
                hint: widget.country.momoCodeExample ?? '123456',
                controller: _momoCodeController,
                keyboardType: TextInputType.number,
                prefixIcon: Icons.tag_rounded,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() => _qrGenerated = false),
              ),

            const SizedBox(height: 18),

            // ─── QR code ───
            if (_qrGenerated && _canGenerate) ...[
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: palette.border.withValues(alpha: 0.7),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: QrImageView(
                  data: _qrData,
                  version: QrVersions.auto,
                  size: 220,
                  padding: const EdgeInsets.all(18),
                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _displayRecipient,
                style: GoogleFonts.dmMono(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: palette.accent,
                ),
              ),
              Text(
                'MOMO QR · ${widget.country.name}',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: palette.text2,
                ),
              ),
              const SizedBox(height: 18),
            ] else ...[
              // Placeholder when QR not yet generated
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 48),
                decoration: BoxDecoration(
                  color: palette.surface2,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: palette.border),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.qr_code_2_rounded,
                      size: 56,
                      color: palette.text3,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Enter your MoMo details to generate QR',
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: palette.text2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],

            // ─── Generate QR + Share link buttons ───
            Row(
              children: [
                Expanded(
                  child: CoolButton(
                    label: 'Generate QR',
                    icon: Icons.qr_code_2_rounded,
                    variant: CoolButtonVariant.primary,
                    onTap: _generateQr,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: CoolButton(
                    label: 'Share link',
                    variant: CoolButtonVariant.secondary,
                    onTap: _sharePayload,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PAYMENT REQUEST SHEET
// ═════════════════════════════════════════════════════════════════════════════

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
                    tooltip: 'Close',
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
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
              Icon(Icons.check_circle_rounded, size: 36, color: palette.accent),
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
                  style: GoogleFonts.dmSans(fontSize: 14, color: palette.text2),
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
    // Pre-fill from the card-level controllers.
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
                        ? (_supportsPhoneTap ? 'Starting tap' : 'Writing tag')
                        : (_supportsPhoneTap ? 'Start tap' : 'Write tag'),
                    isLoading: isWriting,
                    onTap: () {
                      final amount = amountCtrl.text.trim();
                      if (recipientValue.isEmpty || amount.isEmpty) {
                        CoolToast.error(context, 'Add amount and MoMo');
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
                              _supportsPhoneTap ? 'Tap ready' : 'Tag ready',
                            );
                          })
                          .catchError((Object _) {
                            setSheetState(() => isWriting = false);
                            if (mounted) {
                              CoolToast.error(this.context, 'Write failed');
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

  Widget _buildHero({
    required CoolPalette palette,
    required bool accessReady,
    required String accessMessage,
  }) {
    final isListening = _isScanning || _isReceiveModeActive;
    final accent = _isScanning
        ? palette.blue
        : _isReceiveModeActive
        ? palette.accent
        : accessReady
        ? palette.blue
        : palette.text;
    final heroIcon = _isScanning
        ? Icons.wifi_tethering_rounded
        : _isReceiveModeActive
        ? Icons.contactless_rounded
        : accessReady
        ? Icons.nfc_rounded
        : Icons.nfc_outlined;
    final statusLabel = _isScanning
        ? 'Listening now'
        : _isReceiveModeActive
        ? 'Tap live'
        : accessReady
        ? 'Ready now'
        : accessMessage;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: isListening ? 0.22 : 0.12),
            palette.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isListening ? accent.withValues(alpha: 0.45) : palette.border,
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 128,
            height: 128,
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final pulse = _pulseController.value;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    if (isListening)
                      _NfcPulseRing(
                        color: accent,
                        scale: 1 + (pulse * 0.45),
                        opacity: 0.22 * (1 - pulse),
                      ),
                    if (isListening)
                      _NfcPulseRing(
                        color: accent,
                        scale: 1.12 + (pulse * 0.55),
                        opacity: 0.12 * (1 - pulse),
                      ),
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.surface,
                        border: Border.all(
                          color: accent.withValues(alpha: 0.35),
                          width: 1.6,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.18),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Icon(heroIcon, size: 42, color: accent),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'NFC pay',
            style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 10),
          _NfcStatePill(
            icon: isListening ? Icons.radio_button_checked_rounded : heroIcon,
            label: statusLabel,
            color: accent,
          ),
          if (!accessReady && accessMessage.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              accessMessage,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: palette.text2,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionArea({
    required CoolPalette palette,
    required bool showWrite,
    required bool hasReceiveRoute,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = showWrite && constraints.maxWidth >= 560;
        final readPanel = _NfcActionPanel(
          icon: _isScanning ? Icons.wifi_tethering_rounded : Icons.nfc_rounded,
          title: 'Read tag',
          stateLabel: _isScanning ? 'Live' : 'Ready',
          color: _isScanning ? palette.blue : palette.text,
          buttonLabel: _isScanning ? 'Scanning' : 'Read tag',
          buttonVariant: CoolButtonVariant.primary,
          isLoading: _isScanning,
          onTap: _startRead,
        );
        final receivePanel = _NfcActionPanel(
          icon: _supportsPhoneTap
              ? Icons.contactless_rounded
              : Icons.nfc_rounded,
          title: _supportsPhoneTap ? 'Tap receive' : 'Write tag',
          stateLabel: hasReceiveRoute
              ? (_isReceiveModeActive ? 'Live' : 'Ready')
              : 'Locked',
          color: !hasReceiveRoute
              ? palette.text3
              : (_isReceiveModeActive ? palette.accent : palette.accent2),
          buttonLabel: hasReceiveRoute
              ? (_isReceiveModeActive
                    ? 'Update tap'
                    : (_supportsPhoneTap ? 'Tap receive' : 'Write tag'))
              : 'Add MoMo first',
          buttonVariant: CoolButtonVariant.secondary,
          onTap: hasReceiveRoute
              ? _showWriteSheet
              : () {
                  CoolToast.info(context, 'Add MoMo first');
                },
        );

        if (!showWrite) {
          return readPanel;
        }

        if (wide) {
          return Row(
            children: [
              Expanded(child: readPanel),
              const SizedBox(width: 14),
              Expanded(child: receivePanel),
            ],
          );
        }

        return Column(
          children: [readPanel, const SizedBox(height: 14), receivePanel],
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
    final accessMessage = switch (nfcAccess?.kind) {
      AppAccessStateKind.disabledInApp => 'NFC off in app',
      AppAccessStateKind.serviceDisabled => 'NFC off',
      AppAccessStateKind.notAvailable => 'NFC unsupported',
      _ => hasReceiveRoute ? '' : 'Add MoMo first',
    };

    return CoolCard(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            // ─── Editable MoMo number / code + amount ───
            if (_nfcHasCode && _nfcHasNumber) ...[
              Row(
                children: [
                  Expanded(
                    child: _NfcRouteTypeChip(
                      label: 'MoMo Number',
                      isActive:
                          _nfcRecipientType == MomoRecipientType.phoneNumber,
                      onTap: () {
                        setState(
                          () => _nfcRecipientType =
                              MomoRecipientType.phoneNumber,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _NfcRouteTypeChip(
                      label: 'MoMo Code',
                      isActive:
                          _nfcRecipientType == MomoRecipientType.code,
                      onTap: () {
                        setState(
                          () => _nfcRecipientType = MomoRecipientType.code,
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
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
            CoolTextField(
              label: 'Amount (${widget.country.currencyCode})',
              hint: '5,000',
              controller: _nfcAmountController,
              keyboardType: TextInputType.number,
              prefixIcon: Icons.payments_rounded,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 18),

            _buildHero(
              palette: palette,
              accessReady: accessReady,
              accessMessage: accessMessage,
            ),
            if (_supportsPhoneTap &&
                _isReceiveModeActive &&
                activePayload != null) ...[
              const SizedBox(height: 18),
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
            if (nfcAccess == null)
              const CupertinoActivityIndicator()
            else if (nfcAccess.kind == AppAccessStateKind.disabledInApp)
              CoolButton(
                label: 'Enable NFC',
                icon: Icons.nfc_rounded,
                onTap: _enableNfcAccess,
              )
            else if (nfcAccess.kind == AppAccessStateKind.serviceDisabled)
              CoolButton(
                label: 'Open NFC settings',
                icon: Icons.settings_rounded,
                onTap: _openNfcSettings,
              )
            else if (accessReady) ...[
              _buildActionArea(
                palette: palette,
                showWrite: showWrite,
                hasReceiveRoute: hasReceiveRoute,
              ),
              if (_supportsPhoneTap && _isReceiveModeActive) ...[
                const SizedBox(height: 14),
                CoolButton(
                  label: _isActivating ? 'Stopping' : 'Stop receive',
                  variant: CoolButtonVariant.secondary,
                  isLoading: _isActivating,
                  icon: Icons.stop_circle_rounded,
                  onTap: () async {
                    setState(() => _isActivating = true);
                    try {
                      await _nfcHceService.stopPaymentRequest();
                      if (!mounted) {
                        return;
                      }
                      await _refreshNfcAccess();
                      if (!mounted) {
                        return;
                      }
                      CoolToast.success(this.context, 'Tap off');
                    } catch (_) {
                      if (!mounted) {
                        return;
                      }
                      CoolToast.error(this.context, 'Stop failed');
                    } finally {
                      if (mounted) {
                        setState(() => _isActivating = false);
                      }
                    }
                  },
                ),
              ],
              if (!showWrite)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 14,
                        color: palette.text3,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Read only',
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: palette.text3,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NfcPulseRing extends StatelessWidget {
  const _NfcPulseRing({
    required this.color,
    required this.scale,
    required this.opacity,
  });

  final Color color;
  final double scale;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: color.withValues(alpha: opacity),
            width: 10,
          ),
        ),
      ),
    );
  }
}

class _NfcStatePill extends StatelessWidget {
  const _NfcStatePill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: palette.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _NfcActionPanel extends StatelessWidget {
  const _NfcActionPanel({
    required this.icon,
    required this.title,
    required this.stateLabel,
    required this.color,
    required this.buttonLabel,
    required this.onTap,
    this.buttonVariant = CoolButtonVariant.primary,
    this.isLoading = false,
  });

  final IconData icon;
  final String title;
  final String stateLabel;
  final Color color;
  final String buttonLabel;
  final VoidCallback onTap;
  final CoolButtonVariant buttonVariant;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 22, color: color),
              ),
              const Spacer(),
              _NfcStatePill(
                icon: Icons.circle,
                label: stateLabel,
                color: color,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 14),
          CoolButton(
            label: buttonLabel,
            icon: icon,
            variant: buttonVariant,
            isLoading: isLoading,
            onTap: onTap,
          ),
        ],
      ),
    );
  }
}

class _NfcRouteTypeChip extends StatelessWidget {
  const _NfcRouteTypeChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Semantics(
      button: true,
      selected: isActive,
      label: '$label option',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? palette.accentGlow : palette.surface2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isActive ? palette.accent : palette.border,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isActive ? palette.accent : palette.text2,
            ),
          ),
        ),
      ),
    );
  }
}
