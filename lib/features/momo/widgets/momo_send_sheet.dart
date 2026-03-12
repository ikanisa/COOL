import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/services/momo_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_text_field.dart';
import '../../../shared/widgets/cool_toast.dart';

// ═════════════════════════════════════════════════════════════════════════════
// SEND MONEY BOTTOM SHEET
// ═════════════════════════════════════════════════════════════════════════════

class MomoSendMoneySheet extends StatefulWidget {
  const MomoSendMoneySheet({
    required this.country,
    required this.momoNumber,
    this.momoCode,
    super.key,
  });

  final CoolCountry country;
  final String momoNumber;
  final String? momoCode;

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
    _recipientType = MomoRecipientType.phoneNumber;
  }

  Future<void> _confirmSend() async {
    if (_isSubmitting) {
      return;
    }

    final recipient = _recipientController.text.trim();
    final amount = int.tryParse(
      _amountController.text.replaceAll(RegExp(r'[^0-9]'), ''),
    );

    if (recipient.isEmpty || amount == null || amount <= 0) {
      CoolToast.error(context, 'Enter a valid recipient and amount.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await MomoService.instance.initiatePayment(
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
        'Unable to open the ${widget.country.name} USSD flow.',
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  void dispose() {
    _recipientController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
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
                'Send Money',
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface3,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.public_rounded,
                      size: 16,
                      color: AppColors.text2,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${widget.country.displayName} · ${widget.country.currencyCode} · ${widget.country.dialCode}\nFrom: ${widget.momoNumber}',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text2,
                          height: 1.4,
                        ),
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
                        label: 'MoMo Number',
                        isActive:
                            _recipientType == MomoRecipientType.phoneNumber,
                        onTap: () {
                          setState(
                            () =>
                                _recipientType = MomoRecipientType.phoneNumber,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MomoRouteTypeChip(
                        label: 'MoMo Code',
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

              // Recipient
              CoolTextField(
                label: _recipientType == MomoRecipientType.code
                    ? 'Merchant MoMo Code'
                    : 'Recipient Phone or User ID',
                hint: _recipientType == MomoRecipientType.code
                    ? (widget.momoCode?.trim().isNotEmpty == true
                          ? widget.momoCode!.trim()
                          : '123456')
                    : '${widget.country.dialCode} 91234567 or #392847',
                controller: _recipientController,
                keyboardType: _recipientType == MomoRecipientType.code
                    ? TextInputType.number
                    : TextInputType.phone,
                prefixIcon: _recipientType == MomoRecipientType.code
                    ? Icons.tag_rounded
                    : Icons.person_rounded,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),

              // Amount
              CoolTextField(
                label: 'Amount (${widget.country.currencyCode})',
                hint: '5,000',
                controller: _amountController,
                keyboardType: TextInputType.number,
                prefixIcon: Icons.payments_rounded,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 16),

              Text(
                'Completes via ${widget.country.name} USSD.',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text2,
                ),
              ),
              const SizedBox(height: 18),

              CoolButton(
                label: 'Confirm Send',
                isLoading: _isSubmitting,
                onTap: _confirmSend,
              ),
            ],
          ),
        ),
      ),
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? AppColors.accentGlow : AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
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
    );
  }
}
