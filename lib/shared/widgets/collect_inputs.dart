import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_component_tokens.dart';
import '../../app/theme/collect_icons.dart';
import '../../app/theme/collect_radius.dart';
import '../../app/theme/collect_spacing.dart';
import '../../app/theme/collect_typography.dart';
import '../../app/theme/collect_runtime_tokens.dart';

class OtpCodeField extends StatelessWidget {
  const OtpCodeField({required this.controller, this.length = 6, super.key});

  final TextEditingController controller;
  final int length;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      maxLength: length,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(length),
      ],
      style: CollectTypography.collectIdDisplay(colors.textPrimary),
      decoration: collectInputDecoration(
        context,
        label: 'Verification code',
        helper: 'Enter the $length-digit WhatsApp code.',
      ).copyWith(counterText: ''),
    );
  }
}

class CollectTextInput extends StatelessWidget {
  const CollectTextInput({
    required this.controller,
    required this.label,
    this.helper,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.maxLines = 1,
    this.textCapitalization = TextCapitalization.none,
    this.autocorrect = false,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final int maxLines;
  final TextCapitalization textCapitalization;
  final bool autocorrect;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType:
          keyboardType ?? (maxLines > 1 ? TextInputType.multiline : null),
      textInputAction:
          textInputAction ??
          (maxLines > 1 ? TextInputAction.newline : TextInputAction.next),
      autofillHints: autofillHints,
      maxLines: maxLines,
      textCapitalization: textCapitalization,
      autocorrect: autocorrect,
      onSubmitted: onSubmitted,
      decoration: collectInputDecoration(context, label: label, helper: helper),
    );
  }
}

class SearchWithClearField extends StatelessWidget {
  const SearchWithClearField({
    required this.controller,
    required this.label,
    required this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CollectRuntimeTokens.inputFill(colors),
        borderRadius: CollectRadius.pillBorder,
        border: Border.all(color: CollectRuntimeTokens.inputBorder(colors)),
        boxShadow: [
          BoxShadow(
            color: CollectRuntimeTokens.inputShadow(colors),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        minLines: 1,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: label,
          prefixIcon: Icon(CollectIcons.search, color: colors.textSecondary),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: CollectSpacing.x4,
            vertical: CollectSpacing.x4,
          ),
        ),
      ),
    );
  }
}

InputDecoration collectInputDecoration(
  BuildContext context, {
  required String label,
  String? helper,
  String? prefix,
}) {
  return CollectComponentTokens.inputDecoration(
    context: context,
    label: label,
    helper: helper,
    prefix: prefix,
  );
}
