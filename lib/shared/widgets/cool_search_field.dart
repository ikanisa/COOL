import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

/// Search-specific text field for list filtering and quick find flows.
class CoolSearchField extends StatefulWidget {
  const CoolSearchField({
    required this.hint,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.debounce = const Duration(milliseconds: 300),
    this.autofocus = false,
    this.enabled = true,
    super.key,
  });

  /// Placeholder text shown when the field is empty.
  final String hint;

  /// External controller. If null, an internal one is used.
  final TextEditingController? controller;

  /// Focus node for keyboard focus management.
  final FocusNode? focusNode;

  /// Called when the text changes (after [debounce] if set).
  final ValueChanged<String>? onChanged;

  /// Called when the user submits (e.g. presses Done).
  final ValueChanged<String>? onSubmitted;

  /// Debounce duration for [onChanged]. Set to [Duration.zero] to disable.
  final Duration debounce;

  /// Whether to autofocus the field on mount.
  final bool autofocus;

  /// Whether the field is interactive.
  final bool enabled;

  @override
  State<CoolSearchField> createState() => _CoolSearchFieldState();
}

class _CoolSearchFieldState extends State<CoolSearchField> {
  late TextEditingController _controller;
  late bool _ownsController;
  Timer? _debounceTimer;
  bool _showClear = false;

  @override
  void initState() {
    super.initState();
    _attachController(widget.controller);
  }

  @override
  void didUpdateWidget(CoolSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _detachController();
      _attachController(widget.controller);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _detachController();
    super.dispose();
  }

  void _attachController(TextEditingController? controller) {
    _ownsController = controller == null;
    _controller = controller ?? TextEditingController();
    _controller.addListener(_onTextChanged);
    _showClear = _controller.text.isNotEmpty;
  }

  void _detachController() {
    _controller.removeListener(_onTextChanged);
    if (_ownsController) {
      _controller.dispose();
    }
  }

  void _onTextChanged() {
    final hasText = _controller.text.isNotEmpty;
    if (_showClear != hasText) {
      setState(() => _showClear = hasText);
    }
    _debounceTimer?.cancel();
    if (widget.onChanged != null) {
      if (widget.debounce == Duration.zero) {
        widget.onChanged!(_controller.text);
      } else {
        _debounceTimer = Timer(widget.debounce, () {
          widget.onChanged!(_controller.text);
        });
      }
    }
  }

  void _clear() {
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final fieldRadius = CoolRadii.lg;

    return Semantics(
      textField: true,
      label: widget.hint,
      hint: widget.hint,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.inputSurface,
          borderRadius: BorderRadius.circular(fieldRadius),
          border: Border.all(color: colors.border),
        ),
        child: TextField(
          controller: _controller,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          enabled: widget.enabled,
          textInputAction: TextInputAction.search,
          onSubmitted: widget.onSubmitted,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.primaryText,
            fontWeight: FontWeight.w500,
          ),
          cursorColor: colors.accent,
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: theme.inputDecorationTheme.hintStyle,
            filled: false,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 13,
            ),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: Icon(
                Icons.search_rounded,
                size: 20,
                color: colors.secondaryText,
              ),
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 0,
              minHeight: 0,
            ),
            suffixIcon: _showClear
                ? IconButton(
                    onPressed: _clear,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: colors.tertiaryText,
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).deleteButtonTooltip,
                  )
                : null,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
      ),
    );
  }
}
