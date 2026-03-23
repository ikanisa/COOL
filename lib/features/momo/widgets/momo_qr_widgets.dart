import 'package:flutter/material.dart';

import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/models/momo_qr_payload.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/phone_validator.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_text_field.dart';
import '../../../shared/widgets/cool_toast.dart';
import 'momo_send_sheet.dart';
import '../../../core/l10n/l10n.dart';

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
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.elevatedBackground,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(CoolRadii.xl),
          topRight: Radius.circular(CoolRadii.xl),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            CoolSpace.x4 + CoolSpace.x1 / 2,
            CoolSpace.x3,
            CoolSpace.x4 + CoolSpace.x1 / 2,
            CoolSpace.x6,
          ),
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
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.primaryText,
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
              SizedBox(height: space.x3),
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
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: colors.appBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: context.l10n.back,
          icon: Icon(Icons.arrow_back_rounded, color: colors.primaryText),
        ),
        title: Text(
          'MOMO QR',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.primaryText,
          ),
        ),
      ),
      body: CoolScreenBackground(
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              CoolSpace.x4 + CoolSpace.x1 / 2,
              CoolSpace.x2,
              CoolSpace.x4 + CoolSpace.x1 / 2,
              CoolSpace.x6,
            ),
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
  final _amountController = TextEditingController();
  late MomoRecipientType _recipientType;
  bool _qrGenerated = false;
  bool _showAmount = false;

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

  int? get _parsedAmount {
    final raw = _amountController.text.replaceAll(RegExp(r'[^0-9]'), '');
    return raw.isEmpty ? null : int.tryParse(raw);
  }

  MomoQrPayload get _payload {
    final amt = _parsedAmount;
    if (amt != null && amt > 0) {
      return MomoQrPayload.paymentRequest(
        recipientValue: _normalizedRecipientValue,
        recipientType: _recipientType,
        amount: amt,
        countryCode: widget.country.isoCode,
      );
    }
    return MomoQrPayload.profile(
      recipientValue: _normalizedRecipientValue,
      recipientType: _recipientType,
      countryCode: widget.country.isoCode,
    );
  }

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
    _amountController.dispose();
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
    final amt = _parsedAmount;
    final String shareText;

    if (amt != null && amt > 0) {
      // Build real USSD code like *182*1*1*781234567*5000#
      final ussdCode = widget.country.buildUssdCode(
        recipientMomo: _activeRecipientRaw,
        amount: amt,
        recipientType: _recipientType,
      );
      shareText =
          'Pay me ${widget.country.currencyCode} $amt on MoMo.\n\n'
          'Dial: $ussdCode\n\n'
          '$_routeLabel: $_displayRecipient';
    } else {
      // No amount — share recipient details with instructions
      shareText =
          'Send me money on ${widget.country.name} MoMo.\n\n'
          '$_routeLabel: $_displayRecipient\n\n'
          'Open your MoMo and send to $_displayRecipient.';
    }

    return SharePlus.instance.share(
      ShareParams(text: shareText, subject: 'MoMo Payment'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return CoolCard(
      child: Padding(
        padding: const EdgeInsets.all(CoolSpace.x5 + CoolSpace.x1 / 2),
        child: Column(
          children: [
            // ─── Route type chips ───
            if (_hasCode && _hasNumber) ...[
              Row(
                children: [
                  Expanded(
                    child: MomoRouteTypeChip(
                      label: 'MoMo Number',
                      isActive: _recipientType == MomoRecipientType.phoneNumber,
                      onTap: () {
                        setState(
                          () => _recipientType = MomoRecipientType.phoneNumber,
                        );
                      },
                    ),
                  ),
                  SizedBox(width: space.x2 + space.x1 / 2),
                  Expanded(
                    child: MomoRouteTypeChip(
                      label: 'MoMo Code',
                      isActive: _recipientType == MomoRecipientType.code,
                      onTap: () {
                        setState(() => _recipientType = MomoRecipientType.code);
                      },
                    ),
                  ),
                ],
              ),
              SizedBox(height: space.x4 + space.x1 / 2),
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

            SizedBox(height: space.x3),

            // ─── Optional amount ───
            if (_showAmount)
              CoolTextField(
                label: 'Amount (${widget.country.currencyCode}) — optional',
                hint: '5,000',
                controller: _amountController,
                keyboardType: TextInputType.number,
                prefixIcon: Icons.payments_rounded,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() => _qrGenerated = false),
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _showAmount = true),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(
                    'Add amount (optional)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

            SizedBox(height: space.x4 + space.x1 / 2),

            // ─── QR code ───
            if (_qrGenerated && _canGenerate) ...[
              Container(
                padding: const EdgeInsets.all(CoolSpace.x4 + CoolSpace.x1 / 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.all(
                    Radius.circular(CoolRadii.md),
                  ),
                  border: Border.all(
                    color: colors.border.withValues(alpha: 0.7),
                  ),
                  boxShadow: CoolShadows.clay(brightness, strength: 0.32),
                ),
                child: QrImageView(
                  data: _qrData,
                  version: QrVersions.auto,
                  size: 220,
                  padding: const EdgeInsets.all(
                    CoolSpace.x4 + CoolSpace.x1 / 2,
                  ),
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
              SizedBox(height: space.x3),
              Text(
                _displayRecipient,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.accent,
                ),
              ),
              Text(
                'MOMO QR · ${widget.country.name}',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: colors.secondaryText,
                ),
              ),
              SizedBox(height: space.x4 + space.x1 / 2),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: CoolSpace.x9),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: const BorderRadius.all(
                    Radius.circular(CoolRadii.lg),
                  ),
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.qr_code_2_rounded,
                      size: 56,
                      color: colors.tertiaryText,
                    ),
                    SizedBox(height: space.x3),
                    Text(
                      'Enter your MoMo details to get QR',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: space.x4 + space.x1 / 2),
            ],

            // ─── Generate QR + Share link buttons ───
            Row(
              children: [
                Expanded(
                  child: CoolButton(
                    label: 'Get QR',
                    icon: Icons.qr_code_2_rounded,
                    variant: CoolButtonVariant.primary,
                    onTap: _generateQr,
                  ),
                ),
                SizedBox(width: space.x2 + space.x1 / 2),
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
