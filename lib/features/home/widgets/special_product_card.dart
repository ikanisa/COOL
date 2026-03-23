import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/country_catalog.dart' show MomoRecipientType;
import '../../../core/services/momo_service.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../admin/models/special_product.dart';
import '../../momo/providers/momo_service_provider.dart';

/// Customer-facing card for a special product with USSD auto-launch CTA.
class SpecialProductCard extends ConsumerStatefulWidget {
  const SpecialProductCard({super.key, required this.product});

  final SpecialProduct product;

  @override
  ConsumerState<SpecialProductCard> createState() => _SpecialProductCardState();
}

class _SpecialProductCardState extends ConsumerState<SpecialProductCard> {
  bool _launching = false;

  Future<void> _launchUssd() async {
    setState(() => _launching = true);
    try {
      final momo = ref.read(momoServiceProvider);
      final recipientType = widget.product.momoRecipientType == 'code'
          ? MomoRecipientType.code
          : MomoRecipientType.phoneNumber;
      await momo.initiatePayment(
        recipientMomo: widget.product.momoRecipient,
        amount: widget.product.amount,
        reference:
            'SP-${widget.product.slug}-${DateTime.now().millisecondsSinceEpoch}',
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
    final text = context.coolText;
    final radii = context.coolRadii;
    final space = context.coolSpace;
    final theme = Theme.of(context);

    return CoolCard(
      useGradient: true,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(accent, Colors.black, 0.75)!,
          Color.lerp(accent, Colors.black, 0.65)!,
        ],
      ),
      borderRadius: radii.lg,
      borderColor: accent.withValues(alpha: 0.3),
      padding: EdgeInsets.all(space.x5),
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
                  borderRadius: BorderRadius.all(Radius.circular(radii.sm)),
                ),
                alignment: Alignment.center,
                child: Icon(p.icon, size: 20, color: accentLight),
              ),
              SizedBox(width: space.x3),
              Expanded(
                child: Text(
                  p.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: accentLight,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: space.x2,
                  vertical: space.x1,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: const BorderRadius.all(
                    Radius.circular(CoolRadii.pill),
                  ),
                  border: Border.all(color: accent.withValues(alpha: 0.4)),
                ),
                child: Text(
                  p.targetAudience,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: accentLight,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: space.x4),
          Wrap(
            spacing: space.x3,
            runSpacing: space.x3,
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
          SizedBox(height: space.x4),
          Semantics(
            button: true,
            label: 'Pay ${p.title} with MoMo',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _launching ? null : _launchUssd,
                borderRadius: const BorderRadius.all(
                  Radius.circular(CoolRadii.pill),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: CoolTapTargets.minimum,
                  ),
                  child: Ink(
                    decoration: BoxDecoration(
                      color: accentLight.withValues(alpha: 0.15),
                      borderRadius: const BorderRadius.all(
                        Radius.circular(CoolRadii.pill),
                      ),
                      border: Border.all(
                        color: accentLight.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: space.x3,
                        vertical: space.x2,
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
                          SizedBox(width: space.x1),
                          Text(
                            'Pay Now',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: accentLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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
    final text = context.coolText;
    final radii = context.coolRadii;
    final space = context.coolSpace;
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.pill)),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: space.x3, vertical: space.x1),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: accentLight.withValues(alpha: 0.7),
              ),
            ),
            Text(
              value,
              style: text.mono(
                theme.textTheme.bodySmall,
                color: accentLight,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
