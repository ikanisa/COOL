import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

/// A compact key-value row for displaying stats and metrics.
///
/// Replaces `_StatRow` and any ad-hoc `Row(label, Spacer, value)` patterns.
///
/// ```dart
/// CoolMetricRow(label: 'Balance', value: '125,000 RWF')
/// CoolMetricRow(label: 'Members', valueWidget: CoolBadge(label: '12'))
/// CoolMetricRow.mono(label: 'Code', value: '*182*8*1#')
/// ```
class CoolMetricRow extends StatelessWidget {
  const CoolMetricRow({
    required this.label,
    this.value,
    this.valueWidget,
    this.useMono = false,
    this.labelColor,
    this.valueColor,
    super.key,
  }) : assert(
         value != null || valueWidget != null,
         'Either value or valueWidget must be provided',
       );

  /// Convenience constructor for monospace values (codes, amounts).
  const CoolMetricRow.mono({
    required this.label,
    required String this.value,
    this.labelColor,
    this.valueColor,
    super.key,
  }) : valueWidget = null,
       useMono = true;

  /// Short label — keep to ≤2 words.
  final String label;

  /// Text value. Ignored if [valueWidget] is provided.
  final String? value;

  /// Custom widget for the value position (badge, chip, etc.).
  final Widget? valueWidget;

  /// Use DM Mono for the value (good for codes and amounts).
  final bool useMono;

  /// Override label color.
  final Color? labelColor;

  /// Override value color.
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CoolSpace.x1 + 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: text.mobiLabel(color: labelColor ?? colors.tertiaryText),
          ),
          const SizedBox(width: CoolSpace.x4),
          Flexible(
            child:
                valueWidget ??
                Text(
                  value!,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: useMono
                      ? text.mono(
                          null,
                          color: valueColor ?? colors.primaryText,
                          fontWeight: FontWeight.w700,
                        )
                      : text.display(
                          null,
                          color: valueColor ?? colors.primaryText,
                          fontWeight: FontWeight.w700,
                        ),
                ),
          ),
        ],
      ),
    );
  }
}
