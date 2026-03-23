import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/cool_foundations.dart';
import '../../core/theme/rs_colors.dart';

/// Grid of preset + optional custom amount chips.
///
/// Used for initiative contribution and donation flows.
class RsAmountSelector extends StatefulWidget {
  const RsAmountSelector({
    required this.amounts,
    required this.onAmountSelected,
    this.allowCustom = false,
    this.selectedAmount,
    super.key,
  });

  final List<int> amounts;
  final ValueChanged<int> onAmountSelected;
  final bool allowCustom;
  final int? selectedAmount;

  @override
  State<RsAmountSelector> createState() => _RsAmountSelectorState();
}

class _RsAmountSelectorState extends State<RsAmountSelector> {
  bool _showCustomField = false;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _selectPreset(int amount) {
    setState(() => _showCustomField = false);
    widget.onAmountSelected(amount);
  }

  void _submitCustom() {
    final value = int.tryParse(_controller.text.trim());
    if (value != null && value > 0) {
      widget.onAmountSelected(value);
      setState(() => _showCustomField = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final space = context.coolSpace;
    final chips = <Widget>[
      ...widget.amounts.map(
        (amount) => _Chip(
          label: '$amount RWF',
          isSelected: widget.selectedAmount == amount,
          onTap: () => _selectPreset(amount),
        ),
      ),
      if (widget.allowCustom)
        _Chip(
          label: 'Custom amount',
          isSelected: _showCustomField,
          isCustom: true,
          onTap: () => setState(() => _showCustomField = !_showCustomField),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
          crossAxisCount: 3,
          mainAxisSpacing: space.x2 + 2,
          crossAxisSpacing: space.x2 + 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.4,
          children: chips,
        ),
        if (_showCustomField) ...[
          SizedBox(height: space.x3),
          Row(
            children: [
              Expanded(
                child: _CustomAmountField(
                  controller: _controller,
                  onSubmitted: _submitCustom,
                ),
              ),
              SizedBox(width: space.x2 + 2),
              _ConfirmCustomAmountButton(
                semanticLabel: context.l10n.confirmCustomAmount,
                onTap: _submitCustom,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _CustomAmountField extends StatelessWidget {
  const _CustomAmountField({
    required this.controller,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final theme = Theme.of(context);

    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
      ],
      style: text.mono(
        theme.textTheme.labelLarge,
        fontWeight: FontWeight.w600,
        color: colors.primaryText,
      ),
      decoration: InputDecoration(
        hintText: 'Enter amount',
        hintStyle: text.rayon(
          theme.textTheme.labelMedium,
          color: colors.tertiaryText,
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: space.x3 + 2,
          vertical: space.x3,
        ),
        filled: true,
        fillColor: colors.inputSurface,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radii.sm),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radii.sm),
          borderSide: const BorderSide(color: RsColors.rsBlueLight),
        ),
      ),
      onSubmitted: (_) => onSubmitted(),
    );
  }
}

class _ConfirmCustomAmountButton extends StatelessWidget {
  const _ConfirmCustomAmountButton({
    required this.semanticLabel,
    required this.onTap,
  });

  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radii = context.coolRadii;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radii.sm),
          child: Ink(
            width: CoolTapTargets.minimum,
            height: CoolTapTargets.minimum,
            decoration: BoxDecoration(
              color: RsColors.rsBlue,
              borderRadius: BorderRadius.circular(radii.sm),
            ),
            child: const Icon(
              Icons.check_rounded,
              color: RsColors.rsWhite,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.isCustom = false,
  });

  final String label;
  final bool isSelected;
  final bool isCustom;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final radii = context.coolRadii;
    final theme = Theme.of(context);

    final Color background;
    final Color border;
    final Color textColor;

    if (isCustom) {
      background = RsColors.rsGold.withValues(alpha: isSelected ? 0.22 : 0.10);
      border = RsColors.rsGold.withValues(alpha: isSelected ? 0.6 : 0.3);
      textColor = RsColors.rsGoldLight;
    } else if (isSelected) {
      background = RsColors.rsBlueGlow;
      border = RsColors.rsBlueBorder;
      textColor = RsColors.rsBluePale;
    } else {
      background = colors.inputSurface;
      border = colors.border;
      textColor = colors.primaryText;
    }

    return Semantics(
      button: true,
      label: isCustom ? 'Enter custom amount' : 'Select $label',
      selected: isSelected,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radii.sm),
          child: AnimatedContainer(
            duration: CoolMotion.quick,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(radii.sm),
              border: Border.all(color: border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: CoolSpace.x2),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: text.mono(
                theme.textTheme.labelMedium,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
