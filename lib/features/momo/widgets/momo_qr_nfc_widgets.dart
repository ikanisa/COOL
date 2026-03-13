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
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/phone_validator.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
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
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
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
  final _amountController = TextEditingController();
  late MomoRecipientType _recipientType;
  int? _paymentRequestAmount;

  bool get _hasNumber => widget.momoNumber.trim().isNotEmpty;
  bool get _hasCode => widget.momoCode?.trim().isNotEmpty ?? false;

  int? get _draftAmount {
    return int.tryParse(
      _amountController.text.replaceAll(RegExp(r'[^0-9]'), ''),
    );
  }

  String get _routeLabel =>
      _recipientType == MomoRecipientType.code ? 'MoMo Code' : 'MoMo Number';

  String get _normalizedRecipientValue => switch (_recipientType) {
    MomoRecipientType.phoneNumber => widget.country.buildE164Phone(
      widget.momoNumber,
    ),
    MomoRecipientType.code => widget.country.normalizeMerchantCode(
      widget.momoCode ?? '',
    ),
  };

  String get _displayRecipient => switch (_recipientType) {
    MomoRecipientType.phoneNumber => PhoneValidator.formatMomoDisplay(
      widget.momoNumber,
      widget.country,
    ),
    MomoRecipientType.code => widget.momoCode?.trim() ?? '',
  };

  bool get _paymentRequestActive =>
      _paymentRequestAmount != null && _paymentRequestAmount! > 0;

  bool get _hasDraftPaymentAmount => _draftAmount != null && _draftAmount! > 0;

  bool get _draftMatchesGenerated => _draftAmount == _paymentRequestAmount;

  bool get _needsPaymentQrGeneration =>
      _hasDraftPaymentAmount && !_draftMatchesGenerated;

  MomoQrPayload get _payload => _paymentRequestActive
      ? MomoQrPayload.paymentRequest(
          recipientValue: _normalizedRecipientValue,
          recipientType: _recipientType,
          amount: _paymentRequestAmount!,
          countryCode: widget.country.isoCode,
        )
      : MomoQrPayload.profile(
          recipientValue: _normalizedRecipientValue,
          recipientType: _recipientType,
          countryCode: widget.country.isoCode,
        );

  String get _qrData => _payload.toQrData(widget.country);

  String get _qrGuidance => _paymentRequestActive
      ? 'Manual payment QR is active. When another phone scans it, the dialer opens with ${widget.country.name} MoMo USSD already prepared.'
      : 'Recipient profile QR is active. Enter an amount, then tap Generate payment QR when you want a scanner to open the USSD dialer automatically.';

  String get _amountLabel {
    final amount = _paymentRequestAmount;
    if (amount == null || amount <= 0) {
      return 'Open amount';
    }
    return '${NumberFormat.decimalPattern('en').format(amount)} ${widget.country.currencyCode}';
  }

  String get _draftAmountLabel {
    final amount = _draftAmount;
    if (amount == null || amount <= 0) {
      return 'Enter an amount to create a payment QR';
    }
    return '${NumberFormat.decimalPattern('en').format(amount)} ${widget.country.currencyCode}';
  }

  @override
  void initState() {
    super.initState();
    _recipientType = _hasCode
        ? MomoRecipientType.code
        : MomoRecipientType.phoneNumber;
    _amountController.addListener(_handleAmountChanged);
  }

  @override
  void dispose() {
    _amountController
      ..removeListener(_handleAmountChanged)
      ..dispose();
    super.dispose();
  }

  void _handleAmountChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _generatePaymentQr() {
    final amount = _draftAmount;
    if (amount == null || amount <= 0) {
      CoolToast.error(context, 'Enter a valid amount to generate payment QR.');
      return;
    }

    setState(() => _paymentRequestAmount = amount);
    CoolToast.success(context, 'Payment QR generated.');
  }

  void _useProfileQr() {
    setState(() => _paymentRequestAmount = null);
  }

  Future<void> _sharePayload() {
    final shareText = _payload.canLaunchImmediately
        ? 'Pay $_amountLabel via ${widget.country.name} MoMo using $_routeLabel $_displayRecipient.\n$_qrData'
        : 'Pay me via ${widget.country.name} MoMo on COOL using $_routeLabel $_displayRecipient.\n${_payload.toAppLinkUri()}';
    return SharePlus.instance.share(
      ShareParams(
        text: shareText,
        subject: _payload.canLaunchImmediately
            ? 'MoMo payment request'
            : 'My MoMo payment QR',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.qr_code_2_rounded,
                    size: 20,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'My QR code',
                        style: GoogleFonts.dmSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Bright-light, long-range QR for receive and manual pay requests',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: AppColors.text2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_hasCode && _hasNumber) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _NfcRouteTypeChip(
                      label: 'MoMo Code',
                      isActive: _recipientType == MomoRecipientType.code,
                      onTap: () {
                        setState(() => _recipientType = MomoRecipientType.code);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
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
                ],
              ),
            ],
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _routeLabel,
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text2,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _displayRecipient,
                    style: GoogleFonts.dmMono(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${widget.country.name} · ${widget.country.currencyCode} · $_amountLabel',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            CoolTextField(
              label: 'Amount (${widget.country.currencyCode})',
              hint: 'Enter amount, then tap Generate payment QR',
              controller: _amountController,
              keyboardType: TextInputType.number,
              prefixIcon: Icons.payments_rounded,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _needsPaymentQrGeneration
                    ? AppColors.accentGlow
                    : AppColors.surface3,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _needsPaymentQrGeneration
                      ? AppColors.accent
                      : AppColors.border,
                ),
              ),
              child: Text(
                _paymentRequestActive && !_needsPaymentQrGeneration
                    ? 'Active payment amount: $_amountLabel'
                    : _draftAmountLabel,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _needsPaymentQrGeneration
                      ? AppColors.accent
                      : AppColors.text2,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: CoolButton(
                    label: _paymentRequestActive
                        ? 'Use profile QR'
                        : 'Profile QR',
                    variant: CoolButtonVariant.secondary,
                    onTap: _useProfileQr,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: CoolButton(
                    label: _paymentRequestActive
                        ? (_needsPaymentQrGeneration
                              ? 'Update payment QR'
                              : 'Regenerate payment QR')
                        : 'Generate payment QR',
                    onTap: _generatePaymentQr,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _paymentRequestActive
                    ? AppColors.accentGlow
                    : AppColors.surface3,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _paymentRequestActive
                      ? AppColors.accent
                      : AppColors.border,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _paymentRequestActive
                        ? Icons.flash_on_rounded
                        : Icons.qr_code_2_rounded,
                    size: 18,
                    color: _paymentRequestActive
                        ? AppColors.accent
                        : AppColors.text2,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _qrGuidance,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _paymentRequestActive
                            ? AppColors.accent
                            : AppColors.text2,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.border.withValues(alpha: 0.7),
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
                color: AppColors.accent,
              ),
            ),
            Text(
              _paymentRequestActive
                  ? 'Manual payment QR · ${widget.country.name} · ${widget.country.currencyCode}'
                  : 'Recipient profile QR · ${widget.country.name} · ${widget.country.currencyCode}',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.text2,
              ),
            ),
            const SizedBox(height: 18),
            CoolButton(
              label: _paymentRequestActive
                  ? 'Share payment link'
                  : 'Share receive link',
              onTap: _sharePayload,
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

class MomoPaymentRequestSheet extends ConsumerStatefulWidget {
  const MomoPaymentRequestSheet({
    required this.country,
    required this.momoNumber,
    this.momoCode,
    super.key,
  });

  final CoolCountry country;
  final String momoNumber;
  final String? momoCode;

  @override
  ConsumerState<MomoPaymentRequestSheet> createState() =>
      _MomoPaymentRequestSheetState();
}

class _MomoPaymentRequestSheetState extends ConsumerState<MomoPaymentRequestSheet> {
  final _payerController = TextEditingController();
  final _amountController = TextEditingController();
  late MomoRecipientType _recipientType;
  String? _payerName;

  bool get _hasNumber => widget.momoNumber.trim().isNotEmpty;
  bool get _hasCode => widget.momoCode?.trim().isNotEmpty ?? false;

  String get _displayRecipient => switch (_recipientType) {
    MomoRecipientType.phoneNumber => PhoneValidator.formatMomoDisplay(
      widget.momoNumber,
      widget.country,
    ),
    MomoRecipientType.code => widget.momoCode?.trim() ?? '',
  };

  String get _normalizedRecipient => switch (_recipientType) {
    MomoRecipientType.phoneNumber => widget.country.buildE164Phone(
      widget.momoNumber,
    ),
    MomoRecipientType.code => widget.country.normalizeMerchantCode(
      widget.momoCode ?? '',
    ),
  };

  int? get _amount =>
      int.tryParse(_amountController.text.replaceAll(RegExp(r'[^0-9]'), ''));

  String? get _payerNumberError {
    return PhoneValidator.validateMomoNumberForCountry(
      _payerController.text,
      widget.country,
    );
  }

  bool get _canShare {
    final amount = _amount;
    return amount != null &&
        amount > 0 &&
        (_payerNumberError == null) &&
        _payerController.text.trim().isNotEmpty;
  }

  MomoQrPayload get _paymentRequestPayload => MomoQrPayload.paymentRequest(
    recipientValue: _normalizedRecipient,
    recipientType: _recipientType,
    amount: _amount!,
    countryCode: widget.country.isoCode,
    reference: 'REQ-${DateTime.now().millisecondsSinceEpoch}',
  );

  String get _payerDisplayNumber {
    final error = _payerNumberError;
    if (error == null) {
      return PhoneValidator.formatMomoDisplay(
        _payerController.text,
        widget.country,
      );
    }
    return _payerController.text.trim();
  }

  String get _dialerUrl =>
      _paymentRequestPayload.toDialerUri(widget.country).toString();

  String get _fallbackUrl => _paymentRequestPayload.toAppLinkUri().toString();

  String _requestMessage() {
    final amountLabel =
        '${NumberFormat.decimalPattern('en').format(_amount)} ${widget.country.currencyCode}';
    final payerLabel = _payerName == null || _payerName!.trim().isEmpty
        ? 'there'
        : _payerName!.trim();
    return 'Hi $payerLabel, tap this MoMo pay link to send $amountLabel to $_displayRecipient in ${widget.country.name}.\n'
        'Your phone should open the MoMo USSD dialer automatically. Review the amount, enter your MoMo PIN, and pay.\n\n'
        'Pay now: $_dialerUrl\n'
        'Fallback: $_fallbackUrl';
  }

  @override
  void initState() {
    super.initState();
    _recipientType = _hasCode
        ? MomoRecipientType.code
        : MomoRecipientType.phoneNumber;
  }

  @override
  void dispose() {
    _payerController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickPayerFromContacts() async {
    final contacts = await ContactPickerSheet.show(
      context,
      appAccessService: ref.read(appAccessServiceProvider),
      multiSelect: false,
      title: 'Choose payer',
      subtitle: 'Pick the MoMo payer to message',
    );
    if (!mounted || contacts.isEmpty) {
      return;
    }

    final SimpleContact contact = contacts.first;
    final phone = contact.phones.isNotEmpty ? contact.phones.first : '';
    setState(() {
      _payerName = contact.displayName;
      _payerController.text = phone;
    });
  }

  Future<void> _shareBySms() async {
    if (!_canShare) {
      CoolToast.error(context, 'Add a valid amount and payer number first.');
      return;
    }

    final smsUri = Uri(
      scheme: 'sms',
      path: widget.country.buildE164Phone(_payerController.text),
      queryParameters: <String, String>{'body': _requestMessage()},
    );
    final launched = await launchUrl(
      smsUri,
      mode: LaunchMode.externalApplication,
    );
    if (!mounted) {
      return;
    }
    if (!launched) {
      CoolToast.error(context, 'Could not open SMS right now.');
    }
  }

  Future<void> _shareByWhatsApp() async {
    if (!_canShare) {
      CoolToast.error(context, 'Add a valid amount and payer number first.');
      return;
    }

    await WhatsAppContactService.openChat(
      context,
      phoneNumber: widget.country.buildE164Phone(_payerController.text),
      message: _requestMessage(),
      unavailableMessage: 'WhatsApp is not available on this device.',
      failureMessage: 'Could not open WhatsApp right now.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final amount = _amount;
    final requestReady = _canShare;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            22,
            12,
            22,
            22 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border2,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Request payment',
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Create a shareable MoMo pay link for one payer. When they tap it, their phone opens the MoMo USSD dialer and they can enter their MoMo PIN to pay.',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text2,
                    height: 1.45,
                  ),
                ),
                if (_hasCode && _hasNumber) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _NfcRouteTypeChip(
                          label: 'MoMo Code',
                          isActive: _recipientType == MomoRecipientType.code,
                          onTap: () {
                            setState(
                              () => _recipientType = MomoRecipientType.code,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _NfcRouteTypeChip(
                          label: 'MoMo Number',
                          isActive:
                              _recipientType == MomoRecipientType.phoneNumber,
                          onTap: () {
                            setState(
                              () => _recipientType =
                                  MomoRecipientType.phoneNumber,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface3,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Payment goes to',
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text2,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _displayRecipient,
                        style: GoogleFonts.dmMono(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                CoolTextField(
                  label: 'Amount (${widget.country.currencyCode})',
                  hint: '5,000',
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  prefixIcon: Icons.payments_rounded,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),
                CoolTextField(
                  label: 'Payer phone number',
                  hint: '${widget.country.dialCode} 78 123 4567',
                  controller: _payerController,
                  keyboardType: TextInputType.phone,
                  prefixIcon: Icons.person_rounded,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                ),
                if (_payerNumberError != null &&
                    _payerController.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _payerNumberError!,
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.red,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                CoolButton(
                  label: _payerName == null
                      ? 'Pick payer from contacts'
                      : 'Picked: $_payerName',
                  variant: CoolButtonVariant.secondary,
                  onTap: _pickPayerFromContacts,
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: requestReady
                        ? AppColors.accentGlow
                        : AppColors.surface3,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: requestReady ? AppColors.accent : AppColors.border,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        requestReady
                            ? 'Request link ready for $_payerDisplayNumber'
                            : 'Add amount and payer number to build the pay link',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: requestReady
                              ? AppColors.accent
                              : AppColors.text2,
                        ),
                      ),
                      if (requestReady && amount != null) ...[
                        const SizedBox(height: 8),
                        SelectableText(
                          _dialerUrl,
                          style: GoogleFonts.dmMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColors.text,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: CoolButton(
                        label: 'Send via SMS',
                        variant: CoolButtonVariant.secondary,
                        onTap: _shareBySms,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: CoolButton(
                        label: 'Send via WhatsApp',
                        onTap: _shareByWhatsApp,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
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

class _MomoNfcCardState extends State<MomoNfcCard> with WidgetsBindingObserver {
  late final AppAccessService _appAccessService = widget.appAccessService;
  final _nfcHceService = NfcHceService.instance;
  bool _isScanning = false;
  bool _isActivating = false;
  bool _isReceiveModeActive = false;
  bool _supportsPhoneTap = false;
  AppAccessSnapshot? _nfcAccess;
  bool _refreshOnResume = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appAccessService.changes.addListener(_handleAccessServiceChange);
    _refreshNfcAccess();
  }

  @override
  void dispose() {
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
    if (mounted) {
      setState(() {
        _nfcAccess = snapshot;
        _supportsPhoneTap = supportsPhoneTap;
        _isReceiveModeActive = isReceiveModeActive;
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
      CoolToast.error(context, 'Could not open NFC settings');
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _isScanning = false);
      CoolToast.error(context, 'NFC read failed: $e');
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
      CoolToast.error(context, 'This NFC payment payload is incomplete.');
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
      CoolToast.error(context, 'Could not launch the USSD payment flow.');
    }
  }

  void _showReadResult(NfcReadResult result) {
    final recipientLabel = result.recipientType == MomoRecipientType.code
        ? 'MoMo Code'
        : 'MoMo Number';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Icon(
              Icons.check_circle_rounded,
              size: 36,
              color: AppColors.accent,
            ),
            const SizedBox(height: 12),
            Text(
              result.hasPaymentData ? 'Payment Tag Found' : 'Tag Read',
              style: GoogleFonts.dmSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
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
                'No readable data on this tag',
                style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.text2),
              ),
            const SizedBox(height: 18),
            if (result.hasPaymentData)
              CoolButton(
                label: 'Pay via USSD',
                onTap: () async {
                  Navigator.pop(context);
                  await _launchPaymentFromTag(result);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _nfcInfoRow(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.text2,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: GoogleFonts.dmMono(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showWriteSheet() {
    final amountCtrl = TextEditingController();
    final supportsCode =
        widget.country.supportsMomoCode &&
        widget.momoCode != null &&
        widget.momoCode!.trim().isNotEmpty;
    final hasNumber = widget.momoNumber.trim().isNotEmpty;
    MomoRecipientType recipientType = supportsCode
        ? MomoRecipientType.code
        : MomoRecipientType.phoneNumber;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        var isWriting = false;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                        color: AppColors.border2,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Receive payment',
                    style: GoogleFonts.dmSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _supportsPhoneTap
                        ? 'Enter the amount to receive, then keep this phone unlocked. Another phone can tap it to open the payment request and launch MoMo USSD.'
                        : 'Enter the amount to receive, then hold this phone near an NFC tag or card. COOL will write a tap-to-pay request using your saved MoMo number or code from Profile.',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AppColors.text2,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (supportsCode && hasNumber) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _NfcRouteTypeChip(
                            label: 'MoMo Code',
                            isActive: recipientType == MomoRecipientType.code,
                            onTap: () {
                              setSheetState(
                                () => recipientType = MomoRecipientType.code,
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _NfcRouteTypeChip(
                            label: 'MoMo Number',
                            isActive:
                                recipientType == MomoRecipientType.phoneNumber,
                            onTap: () {
                              setSheetState(
                                () => recipientType =
                                    MomoRecipientType.phoneNumber,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface3,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
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
                            color: AppColors.text2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          recipientType == MomoRecipientType.code
                              ? widget.momoCode!.trim()
                              : PhoneValidator.formatMomoDisplay(
                                  widget.momoNumber,
                                  widget.country,
                                ),
                          style: GoogleFonts.dmMono(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent,
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
                              ? 'Activating NFC…'
                              : 'Writing NFC…')
                        : 'Activate NFC',
                    isLoading: isWriting,
                    onTap: () {
                      final amount = amountCtrl.text.trim();
                      final recipientValue =
                          recipientType == MomoRecipientType.code
                          ? widget.momoCode?.trim() ?? ''
                          : widget.momoNumber.trim();
                      if (recipientValue.isEmpty || amount.isEmpty) {
                        CoolToast.error(
                          context,
                          'Add an amount and link your MoMo number or code first.',
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
                                  ? 'Phone tap receive is active'
                                  : 'NFC receive payload is ready',
                            );
                          })
                          .catchError((Object e) {
                            setSheetState(() => isWriting = false);
                            if (mounted) {
                              CoolToast.error(this.context, 'Write failed: $e');
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
    final showWrite = !kIsWeb && Platform.isAndroid;
    final nfcAccess = _nfcAccess;
    final accessReady = nfcAccess?.isReady == true;
    final hasReceiveRoute =
        widget.momoNumber.trim().isNotEmpty ||
        (widget.momoCode?.trim().isNotEmpty ?? false);
    final accessMessage = switch (nfcAccess?.kind) {
      AppAccessStateKind.disabledInApp =>
        'NFC is off in COOL. Turn it back on to use tap-based receive and read flows.',
      AppAccessStateKind.serviceDisabled =>
        'NFC is off on this device. Turn it on in system settings.',
      AppAccessStateKind.notAvailable => 'NFC is not available on this device.',
      _ =>
        hasReceiveRoute
            ? (_supportsPhoneTap
                  ? 'Read payment tags or activate phone tap receive using your saved MoMo number or code.'
                  : 'Read payment tags or write a tap-to-pay NFC payload using your saved MoMo number or code.')
            : 'Link a MoMo number or code in Profile before using NFC receive.',
    };

    return CoolCard(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            const Icon(Icons.nfc_rounded, size: 36, color: AppColors.text),
            const SizedBox(height: 12),
            Text(
              'NFC tools',
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              accessMessage,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.text2,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            if (nfcAccess == null)
              const CupertinoActivityIndicator()
            else if (nfcAccess.kind == AppAccessStateKind.disabledInApp)
              CoolButton(label: 'Enable NFC', onTap: _enableNfcAccess)
            else if (nfcAccess.kind == AppAccessStateKind.serviceDisabled)
              CoolButton(label: 'Open NFC settings', onTap: _openNfcSettings)
            else if (accessReady) ...[
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final shouldStack = constraints.maxWidth < 360 && showWrite;
                  final readButton = CoolButton(
                    label: _isScanning ? 'Scanning…' : 'Read Tag',
                    isLoading: _isScanning,
                    onTap: () => _startRead(),
                  );
                  final writeButton = CoolButton(
                    label: hasReceiveRoute
                        ? (_isReceiveModeActive
                              ? 'Update Tap Receive'
                              : (_supportsPhoneTap
                                    ? 'Receive by Phone Tap'
                                    : 'Receive via NFC'))
                        : 'Link MoMo first',
                    variant: CoolButtonVariant.secondary,
                    onTap: hasReceiveRoute
                        ? _showWriteSheet
                        : () {
                            CoolToast.info(
                              context,
                              'Link a MoMo number or code in Profile first.',
                            );
                          },
                  );

                  if (shouldStack) {
                    return Column(
                      children: [
                        readButton,
                        const SizedBox(height: 12),
                        writeButton,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: readButton),
                      if (showWrite) ...[
                        const SizedBox(width: 12),
                        Expanded(child: writeButton),
                      ],
                    ],
                  );
                },
              ),
              if (_supportsPhoneTap && _isReceiveModeActive) ...[
                const SizedBox(height: 12),
                CoolButton(
                  label: _isActivating
                      ? 'Deactivating…'
                      : 'Deactivate Tap Receive',
                  variant: CoolButtonVariant.secondary,
                  isLoading: _isActivating,
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
                      CoolToast.success(
                        this.context,
                        'Phone tap receive is off',
                      );
                    } catch (_) {
                      if (!mounted) {
                        return;
                      }
                      CoolToast.error(
                        this.context,
                        'Could not deactivate phone tap receive.',
                      );
                    } finally {
                      if (mounted) {
                        setState(() => _isActivating = false);
                      }
                    }
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  'Keep this screen open and the phone unlocked while waiting for a payer to tap.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text3,
                  ),
                ),
              ],
              if (!showWrite)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Read only on iOS',
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text3,
                    ),
                  ),
                ),
            ],
          ],
        ),
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
    return Semantics(
      button: true,
      selected: isActive,
      label: '$label option',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? AppColors.accentGlow : AppColors.surface3,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isActive ? AppColors.accent : AppColors.border,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isActive ? AppColors.accent : AppColors.text2,
            ),
          ),
        ),
      ),
    );
  }
}
