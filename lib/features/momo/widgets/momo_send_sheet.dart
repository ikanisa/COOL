import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/services/momo_service.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../core/utils/phone_validator.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_text_field.dart';
import '../../../shared/widgets/cool_toast.dart';

// ═════════════════════════════════════════════════════════════════════════════
// SEND MONEY BOTTOM SHEET
// ═════════════════════════════════════════════════════════════════════════════

class MomoSendMoneySheet extends StatefulWidget {
  const MomoSendMoneySheet({
    required this.country,
    required this.momoNumber,
    required this.momoService,
    this.momoCode,
    this.initialRecipient,
    this.initialAmount,
    this.initialRecipientType = MomoRecipientType.phoneNumber,
    super.key,
  });

  final CoolCountry country;
  final String momoNumber;
  final MomoService momoService;
  final String? momoCode;
  final String? initialRecipient;
  final String? initialAmount;
  final MomoRecipientType initialRecipientType;

  @override
  State<MomoSendMoneySheet> createState() => _MomoSendMoneySheetState();
}

class _MomoSendMoneySheetState extends State<MomoSendMoneySheet> {
  final _recipientController = TextEditingController();
  final _amountController = TextEditingController();
  late MomoRecipientType _recipientType;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _recipientType = widget.country.supportsMomoCode
        ? widget.initialRecipientType
        : MomoRecipientType.phoneNumber;
    _recipientController.text = widget.initialRecipient?.trim() ?? '';
    _amountController.text = widget.initialAmount?.trim() ?? '';
    _recipientController.addListener(_handleDraftChanged);
    _amountController.addListener(_handleDraftChanged);
  }

  void _handleDraftChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _confirmSend() async {
    final l10n = context.l10n;
    if (_isSubmitting) {
      return;
    }

    final recipient = _recipientController.text.trim();
    final amount = int.tryParse(
      _amountController.text.replaceAll(RegExp(r'[^0-9]'), ''),
    );

    if (recipient.isEmpty || amount == null || amount <= 0) {
      CoolToast.error(context, l10n.momoSendValidationError);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await widget.momoService.initiatePayment(
        recipientMomo: recipient,
        amount: amount,
        reference: 'SEND-${DateTime.now().millisecondsSinceEpoch}',
        recipientType: _recipientType,
        countryCode: widget.country.isoCode,
      );

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) {
        return;
      }
      CoolToast.error(context, l10n.momoSendLaunchFailed(widget.country.name));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  void dispose() {
    _recipientController.removeListener(_handleDraftChanged);
    _amountController.removeListener(_handleDraftChanged);
    _recipientController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.coolPalette;
    final displayNumber = PhoneValidator.formatMomoDisplay(
      widget.momoNumber,
      widget.country,
    );
    final hasDisplayNumber = displayNumber.trim().isNotEmpty;
    final recipient = _recipientController.text.trim();
    final amount = int.tryParse(
      _amountController.text.replaceAll(RegExp(r'[^0-9]'), ''),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                      color: palette.border2,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  l10n.sendMoneyTitle,
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: palette.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: palette.border),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.public_rounded,
                        size: 16,
                        color: palette.text2,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${widget.country.displayName} · ${widget.country.currencyCode} · ${widget.country.dialCode}',
                              style: GoogleFonts.dmSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: palette.text,
                              ),
                            ),
                            if (hasDisplayNumber) ...[
                              const SizedBox(height: 2),
                              Text(
                                l10n.momoFromNumber(displayNumber),
                                style: GoogleFonts.dmSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: palette.text2,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (widget.country.supportsMomoCode) ...[
                  Row(
                    children: [
                      Expanded(
                        child: MomoRouteTypeChip(
                          label: l10n.momoRoutePhoneLabel,
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
                      const SizedBox(width: 10),
                      Expanded(
                        child: MomoRouteTypeChip(
                          label: l10n.momoRouteCodeLabel,
                          isActive: _recipientType == MomoRecipientType.code,
                          onTap: () {
                            setState(
                              () => _recipientType = MomoRecipientType.code,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                CoolTextField(
                  label: _recipientType == MomoRecipientType.code
                      ? l10n.momoRecipientCodeLabel
                      : l10n.momoRecipientPhoneLabel,
                  hint: _recipientType == MomoRecipientType.code
                      ? (widget.momoCode?.trim().isNotEmpty == true
                            ? widget.momoCode!.trim()
                            : (widget.country.momoCodeExample ?? '123456'))
                      : widget.country.phoneExampleHint(),
                  controller: _recipientController,
                  keyboardType: _recipientType == MomoRecipientType.code
                      ? TextInputType.number
                      : TextInputType.phone,
                  prefixIcon: _recipientType == MomoRecipientType.code
                      ? Icons.tag_rounded
                      : Icons.person_rounded,
                  autofocus: _recipientController.text.trim().isEmpty,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 14),
                CoolTextField(
                  label: l10n.momoAmountLabel(widget.country.currencyCode),
                  hint: '5,000',
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  prefixIcon: Icons.payments_rounded,
                  autofocus:
                      _recipientController.text.trim().isNotEmpty &&
                      _amountController.text.trim().isEmpty,
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: 16),
                _MomoSendReviewCard(
                  country: widget.country,
                  sourceDisplayNumber: displayNumber,
                  recipient: recipient,
                  amount: amount,
                  recipientType: _recipientType,
                ),
                const SizedBox(height: 18),
                CoolButton(
                  label: l10n.momoContinueToUssd,
                  isLoading: _isSubmitting,
                  onTap: _confirmSend,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MomoSendReviewCard extends StatelessWidget {
  const _MomoSendReviewCard({
    required this.country,
    required this.sourceDisplayNumber,
    required this.recipient,
    required this.amount,
    required this.recipientType,
  });

  final CoolCountry country;
  final String sourceDisplayNumber;
  final String recipient;
  final int? amount;
  final MomoRecipientType recipientType;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final palette = context.coolPalette;
    return Semantics(
      container: true,
      label:
          '${l10n.momoReviewTitle}. ${l10n.momoReviewRecipientLabel}: ${recipient.isEmpty ? l10n.momoReviewMissingRecipient : recipient}. '
          '${l10n.momoReviewAmountLabel}: ${amount == null ? l10n.momoReviewMissingAmount : _formatAmount(amount!, country.currencyCode, localeTag)}.',
      child: CoolCard(
        backgroundColor: palette.surface2,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.momoReviewTitle,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: palette.text,
              ),
            ),
            const SizedBox(height: 12),
            _MomoReviewRow(
              label: l10n.momoReviewRecipientLabel,
              value: recipient.isEmpty
                  ? l10n.momoReviewMissingRecipient
                  : recipient,
              emphasizeValue: recipient.isNotEmpty,
            ),
            const SizedBox(height: 10),
            _MomoReviewRow(
              label: l10n.momoReviewAmountLabel,
              value: amount == null
                  ? l10n.momoReviewMissingAmount
                  : _formatAmount(amount!, country.currencyCode, localeTag),
              emphasizeValue: amount != null,
            ),
            const SizedBox(height: 10),
            _MomoReviewRow(
              label: l10n.momoReviewRouteLabel,
              value: recipientType == MomoRecipientType.code
                  ? l10n.momoRouteCodeLabel
                  : l10n.momoRoutePhoneLabel,
              emphasizeValue: true,
            ),
            if (sourceDisplayNumber.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              _MomoReviewRow(
                label: l10n.momoReviewFromLabel,
                value: sourceDisplayNumber,
                emphasizeValue: true,
              ),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Divider(height: 1, color: palette.border),
            ),
            Text(
              l10n.momoWhatHappensNextTitle,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: palette.text,
              ),
            ),
            const SizedBox(height: 10),
            _MomoStepRow(
              step: '1',
              text: l10n.momoWhatHappensNextOpen(country.name),
            ),
            const SizedBox(height: 8),
            _MomoStepRow(step: '2', text: l10n.momoWhatHappensNextConfirm),
            const SizedBox(height: 8),
            _MomoStepRow(step: '3', text: l10n.momoWhatHappensNextReceipt),
          ],
        ),
      ),
    );
  }

  static String _formatAmount(int amount, String currency, String localeTag) {
    final formatter = NumberFormat.decimalPattern(localeTag);
    return '$currency ${formatter.format(amount)}';
  }
}

class _MomoReviewRow extends StatelessWidget {
  const _MomoReviewRow({
    required this.label,
    required this.value,
    required this.emphasizeValue,
  });

  final String label;
  final String value;
  final bool emphasizeValue;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: palette.text2,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: GoogleFonts.dmMono(
              fontSize: 12,
              fontWeight: emphasizeValue ? FontWeight.w700 : FontWeight.w500,
              color: emphasizeValue ? palette.text : palette.text2,
            ),
          ),
        ),
      ],
    );
  }
}

class _MomoStepRow extends StatelessWidget {
  const _MomoStepRow({required this.step, required this.text});

  final String step;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: palette.accentGlow,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: palette.border),
          ),
          alignment: Alignment.center,
          child: Text(
            step,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: palette.accent,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: palette.text2,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ROUTE TYPE CHIP (Phone vs MoMo Code)
// ═════════════════════════════════════════════════════════════════════════════

class MomoRouteTypeChip extends StatelessWidget {
  const MomoRouteTypeChip({
    required this.label,
    required this.isActive,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final palette = context.coolPalette;
    return Semantics(
      button: true,
      selected: isActive,
      label: '$label route type',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? palette.accentGlow : palette.surface2,
            borderRadius: BorderRadius.circular(12),
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
