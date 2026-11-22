import 'dart:ui' show SemanticsValidationResult;

import 'package:flutter/material.dart';

import '../../core/utils/money_format.dart';
import '../../shared/widgets/collect_components.dart';

/// A single whole-RWF edit control with a stable name and associated errors.
///
/// Editing keeps the selected amount typography and normal cursor scrolling.
/// When the value cannot fit, a separate complete readback wraps at grouping
/// separators using the existing readable title role. It never scales the
/// entire monetary value down or changes the formatter's numeric boundary.
class ContributionAmountInput extends StatelessWidget {
  const ContributionAmountInput({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.onChanged,
    required this.onSubmitted,
    this.errorText,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final String? errorText;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final scaler = MediaQuery.textScalerOf(context);
    final amountStyle = CollectTypography.amountHero(colors.textPrimary);
    final currencyLabel = Text(
      'RWF',
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        color: colors.textMuted,
        fontWeight: CollectTypography.weightSemibold,
      ),
    );
    final field = ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) => LayoutBuilder(
        builder: (context, constraints) {
          final needsReadback =
              value.text.isNotEmpty &&
              !_fitsAmount(
                context,
                value.text,
                amountStyle,
                constraints.maxWidth,
              );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                key: const ValueKey('contribution_amount_input_semantics'),
                label: '$label, RWF',
                validationResult: errorText == null
                    ? SemanticsValidationResult.none
                    : SemanticsValidationResult.invalid,
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: const [RwfAmountInputFormatter()],
                  onChanged: (_) => onChanged(),
                  onSubmitted: (_) => onSubmitted(),
                  style: amountStyle,
                  decoration: InputDecoration(
                    hint: ExcludeSemantics(
                      child: Text(
                        '0',
                        style: amountStyle.copyWith(color: colors.textMuted),
                      ),
                    ),
                    errorText: errorText,
                    errorMaxLines: 10,
                    errorStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.dangerForeground,
                      fontWeight: CollectTypography.weightSemibold,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              if (needsReadback) ...[
                CollectSpacing.gap8,
                Text(
                  _wrappableAmount('RWF ${value.text}'),
                  key: const ValueKey('contribution_amount_full_value'),
                  semanticsLabel: 'RWF ${value.text}',
                  style: _readableAmountStyle(context, amountStyle),
                  textDirection: TextDirection.ltr,
                ),
              ],
            ],
          );
        },
      ),
    );
    if (scaler.scale(1) >= 1.3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [currencyLabel, CollectSpacing.gap4, field],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        currencyLabel,
        CollectSpacing.gapW12,
        Expanded(child: field),
      ],
    );
  }
}

/// Review the complete amount at readable size, including compact/large text.
class ContributionAmountValue extends StatelessWidget {
  const ContributionAmountValue({required this.amountRwf, super.key});

  final int amountRwf;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final value = formatRwf(amountRwf);
      final hero = CollectTypography.amountHero(
        context.collectColors.textPrimary,
      );
      final style = _fitsAmount(context, value, hero, constraints.maxWidth)
          ? hero
          : _readableAmountStyle(context, hero);
      return Text(
        _wrappableAmount(value),
        key: const ValueKey('contribution_review_full_value'),
        semanticsLabel: value,
        style: style,
        textDirection: TextDirection.ltr,
      );
    },
  );
}

String _wrappableAmount(String value) => value.replaceAll(',', ',\u200b');

TextStyle _readableAmountStyle(BuildContext context, TextStyle hero) =>
    hero.copyWith(
      fontSize: Theme.of(context).textTheme.titleLarge?.fontSize ?? 24,
      height: CollectTypography.leadingLabel,
    );

bool _fitsAmount(
  BuildContext context,
  String value,
  TextStyle style,
  double width,
) {
  final painter = TextPainter(
    text: TextSpan(text: value, style: style),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final fits = painter.width + 4 <= width;
  painter.dispose();
  return fits;
}
