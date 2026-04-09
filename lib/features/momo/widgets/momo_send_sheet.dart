import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intl/intl.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/services/momo_service.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/phone_validator.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_text_field.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../providers/momo_risk_provider.dart';
import 'momo_risk_warning_sheet.dart';

part 'momo_send_sheet_content.dart';

class MomoSendMoneySheet extends ConsumerStatefulWidget {
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
  ConsumerState<MomoSendMoneySheet> createState() => _MomoSendMoneySheetState();
}

class _MomoSendMoneySheetState extends ConsumerState<MomoSendMoneySheet> {
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
      // ── Guardian AI: Real-time Risk Prevention ──
      final risk = await ref
          .read(momoRiskProvider.notifier)
          .evaluateRisk(
            recipientNumber: recipient,
            amount: amount,
            currency: widget.country.currencyCode,
          );

      if (risk != null) {
        if (risk.shouldBlock) {
          if (mounted) {
            CoolToast.error(
              context,
              'Transaction blocked for your safety: ${risk.reason}',
            );
            setState(() => _isSubmitting = false);
          }
          return;
        }

        if (risk.shouldWarn) {
          if (mounted) {
            final proceed = await MomoRiskWarningSheet.show(context, risk);
            if (proceed != true) {
              setState(() => _isSubmitting = false);
              return;
            }
          }
        }
      }

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
      CoolToast.error(
        context,
        '${l10n.momoSendLaunchFailed} ${widget.country.name}',
      );
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
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final theme = Theme.of(context);
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
        color: colors.elevatedBackground,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(CoolRadii.xl),
          topRight: Radius.circular(CoolRadii.xl),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            space.x5 + space.x1 / 2,
            space.x3,
            space.x5 + space.x1 / 2,
            space.x5 + space.x1 / 2 + MediaQuery.of(context).viewInsets.bottom,
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
                      color: colors.borderStrong,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(CoolRadii.xs),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: space.x5),
                Text(
                  l10n.sendMoneyTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
                SizedBox(height: space.x5),
                Container(
                  padding: EdgeInsets.all(space.x3),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: const BorderRadius.all(
                      Radius.circular(CoolRadii.sm),
                    ),
                    border: Border.all(color: colors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.public_rounded,
                        size: 16,
                        color: colors.secondaryText,
                      ),
                      SizedBox(width: space.x2),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${widget.country.displayName} · ${widget.country.currencyCode} · ${widget.country.dialCode}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colors.primaryText,
                              ),
                            ),
                            if (hasDisplayNumber) ...[
                              const SizedBox(height: 2),
                              Text(
                                l10n.momoFromNumber(displayNumber),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w500,
                                  color: colors.secondaryText,
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
                const SizedBox(height: CoolSpace.x4),
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
