part of 'collect_financial_components.dart';

class AmountEntryPanel extends StatelessWidget {
  const AmountEntryPanel({
    required this.controller,
    required this.amount,
    required this.quickAmounts,
    required this.onQuickAmount,
    this.label,
    this.detail,
    this.error,
    this.showCurrencyChip = true,
    this.showQuickAmounts = true,
    super.key,
  });

  final TextEditingController controller;
  final int amount;
  final List<int> quickAmounts;
  final ValueChanged<int> onQuickAmount;
  final String? label;
  final String? detail;
  final String? error;
  final bool showCurrencyChip;
  final bool showQuickAmounts;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final effectiveLabel = label?.trim().isNotEmpty == true
        ? label!.trim()
        : 'Amount';
    final amountSemanticValue = amount > 0
        ? formatRwf(amount)
        : 'No amount entered';
    final amountStyle = CollectTypography.amountDisplay(
      colors.textPrimary,
    ).copyWith(fontSize: 44, height: 1.05);
    final prefixStyle = amountStyle.copyWith(color: colors.textSecondary);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '$effectiveLabel entry',
      child: CollectCard(
        emphasis: CollectCardEmphasis.compact,
        padding: CollectSpacing.cardPaddingComfortable,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    label: effectiveLabel,
                    child: ExcludeSemantics(
                      child: Text(
                        effectiveLabel,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: colors.textSecondary,
                              fontWeight: FontWeight.w800,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                if (showCurrencyChip)
                  Semantics(
                    label: 'Currency RWF',
                    child: ExcludeSemantics(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: CollectRuntimeTokens.chipBackground(colors),
                          borderRadius: CollectRadius.pillBorder,
                          border: Border.all(
                            color: CollectRuntimeTokens.inputBorder(colors),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: CollectSpacing.x3,
                            vertical: CollectSpacing.x1,
                          ),
                          child: Text(
                            'RWF',
                            style: CollectTypography.eyebrowLabel(
                              colors.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            CollectSpacing.gap16,
            DecoratedBox(
              decoration: BoxDecoration(
                color: CollectRuntimeTokens.inputFill(colors),
                borderRadius: CollectRadius.panelBorder,
                border: Border.all(
                  color: CollectRuntimeTokens.inputBorder(colors),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: CollectSpacing.x4,
                  vertical: CollectSpacing.x3,
                ),
                child: Semantics(
                  container: true,
                  textField: true,
                  label: '$effectiveLabel field',
                  value: amountSemanticValue,
                  hint: 'Enter amount in Rwandan francs',
                  child: TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [_RwfAmountInputFormatter()],
                    style: amountStyle,
                    maxLines: 1,
                    decoration: InputDecoration(
                      hintText: '0',
                      prefixText: 'RWF ',
                      prefixStyle: prefixStyle,
                      hintStyle: amountStyle.copyWith(color: colors.textMuted),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      isCollapsed: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
            ),
            if (detail != null) ...[
              CollectSpacing.gap8,
              Text(detail!, style: Theme.of(context).textTheme.bodyMedium),
            ],
            if (showQuickAmounts && quickAmounts.isNotEmpty) ...[
              CollectSpacing.gap16,
              Wrap(
                spacing: CollectSpacing.x2,
                runSpacing: CollectSpacing.x2,
                children: [
                  for (final option in quickAmounts)
                    ChoiceChip(
                      label: Text(_compactAmount(option)),
                      selected: amount == option,
                      selectedColor:
                          CollectRuntimeTokens.chipSelectedBackground(colors),
                      backgroundColor: CollectRuntimeTokens.chipBackground(
                        colors,
                      ),
                      showCheckmark: false,
                      side: BorderSide(
                        color: CollectRuntimeTokens.chipBorder(
                          colors,
                          selected: amount == option,
                        ),
                        width: amount == option ? 1.5 : 1,
                      ),
                      labelStyle: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(
                            color: amount == option
                                ? colors.selectedOnAccent
                                : colors.textPrimary,
                            fontWeight: FontWeight.w900,
                          ),
                      onSelected: (_) => onQuickAmount(option),
                    ),
                ],
              ),
            ],
            if (error != null) ...[
              CollectSpacing.gap12,
              Semantics(
                liveRegion: true,
                label: error!,
                child: Text(
                  error!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.danger),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _compactAmount(int amount) {
  if (amount >= 1000000 && amount % 1000000 == 0) {
    return '${amount ~/ 1000000}M';
  }
  if (amount >= 1000 && amount % 1000 == 0) {
    return '${amount ~/ 1000}k';
  }
  return formatRwf(amount);
}

class _RwfAmountInputFormatter extends TextInputFormatter {
  const _RwfAmountInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    final value = int.tryParse(digits);
    if (value == null) return oldValue;
    final formatted = _formatPlainNumber(value);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

String _formatPlainNumber(int value) {
  final raw = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < raw.length; index += 1) {
    if (index > 0 && (raw.length - index) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(raw[index]);
  }
  return buffer.toString();
}
