import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

/// Compact inline text field for admin management screens.
///
/// Renders as a label-above layout with smaller padding and optional save/cancel
/// inline actions. Designed for dense admin surfaces where vertical space is at
/// a premium.
class CoolAdminInlineField extends StatefulWidget {
  const CoolAdminInlineField({
    required this.label,
    this.hint,
    this.controller,
    this.focusNode,
    this.keyboardType,
    this.onChanged,
    this.onSave,
    this.onCancel,
    this.showActions = false,
    this.enabled = true,
    this.maxLines = 1,
    super.key,
  });

  /// Label displayed above the field.
  final String label;

  /// Placeholder text.
  final String? hint;

  /// External controller.
  final TextEditingController? controller;

  /// Focus node.
  final FocusNode? focusNode;

  /// Keyboard type.
  final TextInputType? keyboardType;

  /// Called on text changes.
  final ValueChanged<String>? onChanged;

  /// Called when the save action is pressed (only if [showActions] is true).
  final VoidCallback? onSave;

  /// Called when the cancel action is pressed (only if [showActions] is true).
  final VoidCallback? onCancel;

  /// Whether to show inline save/cancel actions.
  final bool showActions;

  /// Whether the field is interactive.
  final bool enabled;

  /// Max lines for the text field.
  final int maxLines;

  @override
  State<CoolAdminInlineField> createState() => _CoolAdminInlineFieldState();
}

class _CoolAdminInlineFieldState extends State<CoolAdminInlineField> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    const fieldRadius = 10.0;

    final fieldBackground = _isFocused
        ? colors.cardSurfaceStrong
        : colors.inputSurface;
    final fieldBorder = _isFocused
        ? Border.all(color: colors.accent.withValues(alpha: 0.25))
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Label ──────────────────────────────────────────────────
        Semantics(
          label: '${widget.label} field label',
          child: Text(
            widget.label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: _isFocused ? colors.accent : colors.secondaryText,
              letterSpacing: 0.3,
            ),
          ),
        ),
        const SizedBox(height: 6),

        // ── Field + actions ───────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: Semantics(
                textField: true,
                label: widget.label,
                child: AnimatedContainer(
                  duration: CoolMotion.standard,
                  decoration: BoxDecoration(
                    color: fieldBackground,
                    borderRadius: BorderRadius.circular(fieldRadius),
                    border: fieldBorder,
                  ),
                  child: Focus(
                    onFocusChange: (value) {
                      if (_isFocused != value) {
                        setState(() => _isFocused = value);
                      }
                    },
                    child: TextField(
                      controller: widget.controller,
                      focusNode: widget.focusNode,
                      keyboardType: widget.keyboardType,
                      enabled: widget.enabled,
                      maxLines: widget.maxLines,
                      onChanged: widget.onChanged,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: colors.primaryText,
                      ),
                      cursorColor: colors.accent,
                      decoration: InputDecoration(
                        hintText: widget.hint,
                        hintStyle: theme.inputDecorationTheme.hintStyle,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        filled: false,
                        fillColor: Colors.transparent,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.showActions) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: widget.onSave,
                icon: const Icon(CoolIcons.check, size: 18),
                tooltip: 'Save',
                color: colors.success,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
              IconButton(
                onPressed: widget.onCancel,
                icon: const Icon(CoolIcons.close, size: 18),
                tooltip: 'Cancel',
                color: colors.danger,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
            ],
          ],
        ),
      ],
    );
  }
}
