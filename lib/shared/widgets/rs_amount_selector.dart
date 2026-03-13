import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
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

  /// Preset amounts to display (e.g. [500, 1000, 2000, 5000]).
  final List<int> amounts;

  /// Called when a preset or custom amount is confirmed.
  final ValueChanged<int> onAmountSelected;

  /// Whether to show a "Custom ✏️" chip at the end.
  final bool allowCustom;

  /// Currently selected amount (highlights the matching chip).
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
    final chips = <Widget>[
      ...widget.amounts.map((amount) => _Chip(
        label: '${amount.toString()} RWF',
        isSelected: widget.selectedAmount == amount,
        onTap: () => _selectPreset(amount),
      )),
      if (widget.allowCustom)
        _Chip(
          label: 'Custom ✏️',
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
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.4,
          children: chips,
        ),
        if (_showCustomField) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: GoogleFonts.dmMono(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter amount…',
                    hintStyle: GoogleFonts.barlow(
                      fontSize: 14,
                      color: AppColors.text3,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    filled: true,
                    fillColor: AppColors.surface2,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: RsColors.rsBlueLight,
                      ),
                    ),
                  ),
                  onSubmitted: (_) => _submitCustom(),
                ),
              ),
              const SizedBox(width: 10),
              Semantics(
                button: true,
                label: 'Confirm custom amount',
                child: GestureDetector(
                  onTap: _submitCustom,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: RsColors.rsBlue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ── Amount chip ──────────────────────────────────────────────────────

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
    final Color bg;
    final Color border;
    final Color textColor;

    if (isCustom) {
      bg = RsColors.rsGold.withValues(alpha: isSelected ? 0.22 : 0.10);
      border = RsColors.rsGold.withValues(alpha: isSelected ? 0.6 : 0.3);
      textColor = RsColors.rsGoldLight;
    } else if (isSelected) {
      bg = RsColors.rsBlueGlow;
      border = RsColors.rsBlueBorder;
      textColor = AppColors.blue;
    } else {
      bg = AppColors.surface2;
      border = AppColors.border;
      textColor = AppColors.text;
    }

    return Semantics(
      button: true,
      label: isCustom ? 'Enter custom amount' : 'Select $label',
      selected: isSelected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmMono(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}
