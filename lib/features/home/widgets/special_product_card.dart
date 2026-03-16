import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/country_catalog.dart' show MomoRecipientType;
import '../../../core/services/momo_service.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../admin/models/special_product.dart';

/// Customer-facing card for a special product with USSD auto-launch CTA.
class SpecialProductCard extends StatefulWidget {
  const SpecialProductCard({super.key, required this.product});

  final SpecialProduct product;

  @override
  State<SpecialProductCard> createState() => _SpecialProductCardState();
}

class _SpecialProductCardState extends State<SpecialProductCard> {
  bool _launching = false;

  Future<void> _launchUssd() async {
    setState(() => _launching = true);
    try {
      final momo = MomoService(client: Supabase.instance.client);
      final recipientType = widget.product.momoRecipientType == 'code'
          ? MomoRecipientType.code
          : MomoRecipientType.phoneNumber;
      await momo.initiatePayment(
        recipientMomo: widget.product.momoRecipient,
        amount: widget.product.amount,
        reference: 'SP-${widget.product.slug}-${DateTime.now().millisecondsSinceEpoch}',
        recipientType: recipientType,
      );
      if (mounted) {
        CoolToast.success(context, 'MoMo payment launched!');
      }
    } on MomoDialerException {
      if (mounted) {
        CoolToast.error(context, 'USSD unavailable');
      }
    } catch (e) {
      if (mounted) {
        CoolToast.error(context, 'Payment failed: $e');
      }
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final accent = p.accentColor;
    final accentLight = p.accentColorLight;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(accent, Colors.black, 0.75)!,
            Color.lerp(accent, Colors.black, 0.65)!,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(p.icon, size: 20, color: accentLight),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  p.title,
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: accentLight,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  p.targetAudience,
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: accentLight,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Pill(
                label: 'Amount',
                value: p.formattedAmount,
                accent: accent,
                accentLight: accentLight,
              ),
              if (p.interestRate != null)
                _Pill(
                  label: 'Rate',
                  value: p.interestRate!,
                  accent: accent,
                  accentLight: accentLight,
                ),
              if (p.loanMultiplier != null)
                _Pill(
                  label: 'Loan',
                  value: p.loanMultiplier!,
                  accent: accent,
                  accentLight: accentLight,
                ),
            ],
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _launching ? null : _launchUssd,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: accentLight.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: accentLight.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_launching)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accentLight,
                      ),
                    )
                  else
                    Icon(
                      Icons.phone_android_rounded,
                      size: 14,
                      color: accentLight,
                    ),
                  const SizedBox(width: 6),
                  Text(
                    'Pay Now',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: accentLight,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.value,
    required this.accent,
    required this.accentLight,
  });

  final String label;
  final String value;
  final Color accent;
  final Color accentLight;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: accentLight.withValues(alpha: 0.7),
              ),
            ),
            Text(
              value,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: accentLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
