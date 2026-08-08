part of 'collect_financial_components.dart';

class AmountEntryPanel extends StatefulWidget {
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
    this.onSubmitted,
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
  final VoidCallback? onSubmitted;

  @override
  State<AmountEntryPanel> createState() => _AmountEntryPanelState();
}

class _AmountEntryPanelState extends State<AmountEntryPanel> {
  late final FocusNode _amountFocusNode;

  @override
  void initState() {
    super.initState();
    _amountFocusNode = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _amountFocusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) setState(() {});
  }

  void _handleSemanticAmount(String rawAmount) {
    const formatter = _RwfAmountInputFormatter();
    final nextValue = formatter.formatEditUpdate(
      widget.controller.value,
      TextEditingValue(
        text: rawAmount,
        selection: TextSelection.collapsed(offset: rawAmount.length),
      ),
    );
    widget.controller.value = nextValue;
    _amountFocusNode.requestFocus();
  }

  void _handleSemanticTap() {
    _amountFocusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_amountFocusNode.hasFocus) return;
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final usesAccessibilityText =
        MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    final effectiveLabel = widget.label?.trim().isNotEmpty == true
        ? widget.label!.trim()
        : 'Amount';
    final amountStyle = CollectTypography.amountDisplay(colors.textPrimary)
        .copyWith(
          fontSize: CollectTypography.sizeAmountEntry,
          height: CollectTypography.leadingDisplayRelaxed,
        );
    final prefixStyle = amountStyle.copyWith(color: colors.textSecondary);
    final labelWidget = Semantics(
      header: true,
      label: effectiveLabel,
      child: ExcludeSemantics(
        child: Text(
          effectiveLabel,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: colors.textSecondary,
            fontWeight: CollectTypography.weightSemibold,
          ),
          maxLines: usesAccessibilityText ? null : 1,
          overflow: usesAccessibilityText
              ? TextOverflow.visible
              : TextOverflow.ellipsis,
        ),
      ),
    );
    final currencyWidget = Semantics(
      label: 'Currency RWF',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: CollectRuntimeTokens.chipBackground(colors),
            borderRadius: CollectRadius.pillBorder,
            border: Border.all(color: CollectRuntimeTokens.inputBorder(colors)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CollectSpacing.x3,
              vertical: CollectSpacing.x1,
            ),
            child: Text(
              'RWF',
              style: CollectTypography.eyebrowLabel(colors.textMuted),
            ),
          ),
        ),
      ),
    );
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
            if (usesAccessibilityText)
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: CollectSpacing.x3,
                runSpacing: CollectSpacing.x2,
                children: [
                  labelWidget,
                  if (widget.showCurrencyChip) currencyWidget,
                ],
              )
            else
              Row(
                children: [
                  Expanded(child: labelWidget),
                  if (widget.showCurrencyChip) currencyWidget,
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
                  hint: 'Enter amount in Rwandan francs',
                  value: widget.controller.text.isEmpty
                      ? '0'
                      : widget.controller.text,
                  focused: _amountFocusNode.hasFocus,
                  onTap: _handleSemanticTap,
                  onSetText: _handleSemanticAmount,
                  child: ExcludeSemantics(
                    child: MediaQuery.withClampedTextScaling(
                      // Keep formatted RWF values visible inside the single-line
                      // financial field. The surrounding label, detail, and the
                      // explicit text-field semantics still honor accessibility
                      // scaling, while this display-sized numeric value remains
                      // readable instead of horizontally clipping at 200% text.
                      maxScaleFactor: 1.0,
                      child: TextField(
                        controller: widget.controller,
                        focusNode: _amountFocusNode,
                        keyboardType: TextInputType.number,
                        textInputAction: widget.onSubmitted == null
                            ? TextInputAction.next
                            : TextInputAction.done,
                        onSubmitted: widget.onSubmitted == null
                            ? null
                            : (_) => widget.onSubmitted!(),
                        inputFormatters: const [_RwfAmountInputFormatter()],
                        style: amountStyle,
                        maxLines: 1,
                        decoration: InputDecoration(
                          hintText: '0',
                          prefixText: 'RWF ',
                          prefixStyle: prefixStyle,
                          hintStyle: amountStyle.copyWith(
                            color: colors.textMuted,
                          ),
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
              ),
            ),
            if (widget.detail != null) ...[
              CollectSpacing.gap8,
              Text(
                widget.detail!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (widget.showQuickAmounts && widget.quickAmounts.isNotEmpty) ...[
              CollectSpacing.gap16,
              Wrap(
                spacing: CollectSpacing.x2,
                runSpacing: CollectSpacing.x2,
                children: [
                  for (final option in widget.quickAmounts)
                    ChoiceChip(
                      label: Text(_compactAmount(option)),
                      selected: widget.amount == option,
                      selectedColor:
                          CollectRuntimeTokens.chipSelectedBackground(colors),
                      backgroundColor: CollectRuntimeTokens.chipBackground(
                        colors,
                      ),
                      showCheckmark: false,
                      side: BorderSide(
                        color: CollectRuntimeTokens.chipBorder(
                          colors,
                          selected: widget.amount == option,
                        ),
                        width: widget.amount == option ? 1.5 : 1,
                      ),
                      labelStyle: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(
                            color: widget.amount == option
                                ? colors.selectedOnAccent
                                : colors.textPrimary,
                            fontWeight: CollectTypography.weightSemibold,
                          ),
                      onSelected: (_) => widget.onQuickAmount(option),
                    ),
                ],
              ),
            ],
            if (widget.error != null) ...[
              CollectSpacing.gap12,
              Semantics(
                liveRegion: true,
                label: widget.error!,
                child: Text(
                  widget.error!,
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

  static final RegExp _nonDigitPattern = RegExp(r'\D');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(_nonDigitPattern, '');
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
