import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/cool_foundations.dart';

/// Controller for a [CoolOtpField].
///
/// Lets parents clear the field, refocus the first cell, and read the current
/// composed value without reaching into the widget tree.
class CoolOtpController {
  _CoolOtpFieldState? _state;

  String get value => _state?._code ?? '';

  bool get isComplete => _state?._isComplete ?? false;

  void clear({bool focusFirst = true}) {
    _state?._clearAll(focusFirst: focusFirst);
  }
}

/// Segmented one-time-password input field.
///
/// Renders [length] individual digit cells that auto-advance on input and
/// support paste. When all digits are entered, [onComplete] fires with the
/// full code string.
class CoolOtpField extends StatefulWidget {
  const CoolOtpField({
    required this.onComplete,
    this.controller,
    this.length = 6,
    this.autofocus = true,
    this.error,
    this.enabled = true,
    this.onChanged,
    super.key,
  });

  /// Optional external controller for reading and clearing the field.
  final CoolOtpController? controller;

  /// Number of OTP digits.
  final int length;

  /// Fired with the full OTP string when all digits are entered.
  final ValueChanged<String> onComplete;

  /// Whether to autofocus the first cell on mount.
  final bool autofocus;

  /// Error message displayed below the cells.
  final String? error;

  /// Whether the field is interactive.
  final bool enabled;

  /// Fired whenever the composed OTP value changes.
  final ValueChanged<String>? onChanged;

  @override
  State<CoolOtpField> createState() => _CoolOtpFieldState();
}

class _CoolOtpFieldState extends State<CoolOtpField> {
  late List<TextEditingController> _controllers;
  late List<FocusNode> _focusNodes;

  String get _code => _controllers.map((controller) => controller.text).join();

  bool get _isComplete => _code.length == widget.length;

  @override
  void initState() {
    super.initState();
    _initCells();
    widget.controller?._state = this;
  }

  @override
  void didUpdateWidget(CoolOtpField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.length != oldWidget.length) {
      _disposeCells();
      _initCells();
    }
    if (widget.controller != oldWidget.controller) {
      if (oldWidget.controller?._state == this) {
        oldWidget.controller?._state = null;
      }
      widget.controller?._state = this;
    }
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) {
      widget.controller?._state = null;
    }
    _disposeCells();
    super.dispose();
  }

  void _initCells() {
    _controllers = List.generate(widget.length, (_) => TextEditingController());
    _focusNodes = List.generate(widget.length, (_) {
      final node = FocusNode();
      node.addListener(_handleFocusChange);
      return node;
    });
  }

  void _disposeCells() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes) {
      focusNode.removeListener(_handleFocusChange);
      focusNode.dispose();
    }
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onChanged(int index, String value) {
    if (value.length > 1) {
      _handlePaste(value);
      return;
    }

    if (value.isNotEmpty) {
      if (index < widget.length - 1) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
      }
    }

    _notifyChange();
  }

  void _handlePaste(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return;
    }
    for (var i = 0; i < widget.length && i < digits.length; i++) {
      _controllers[i].text = digits[i];
    }
    for (var i = digits.length; i < widget.length; i++) {
      _controllers[i].clear();
    }
    if (digits.length >= widget.length) {
      _focusNodes.last.unfocus();
    } else {
      _focusNodes[digits.length].requestFocus();
    }
    _notifyChange();
  }

  KeyEventResult _onKeyEvent(int index, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.backspace ||
        _controllers[index].text.isNotEmpty ||
        index == 0) {
      return KeyEventResult.ignored;
    }

    _controllers[index - 1].clear();
    _focusNodes[index - 1].requestFocus();
    _notifyChange();
    return KeyEventResult.handled;
  }

  void _clearAll({bool focusFirst = true}) {
    for (final controller in _controllers) {
      controller.clear();
    }
    if (focusFirst && _focusNodes.isNotEmpty) {
      _focusNodes.first.requestFocus();
    }
    _notifyChange();
  }

  void _notifyChange() {
    final code = _code;
    widget.onChanged?.call(code);
    if (code.length == widget.length) {
      widget.onComplete(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final hasError = widget.error != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.length, (index) {
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: space.x1),
              child: SizedBox(
                width: 50,
                height: 58,
                child: Focus(
                  onKeyEvent: (_, event) => _onKeyEvent(index, event),
                  child: Semantics(
                    label: 'OTP digit ${index + 1} of ${widget.length}',
                    textField: true,
                    child: AnimatedContainer(
                      duration: CoolMotion.standard,
                      decoration: BoxDecoration(
                        color: colors.inputSurface,
                        borderRadius: BorderRadius.circular(CoolRadii.sm),
                        border: Border.all(
                          color: hasError
                              ? colors.danger
                              : _focusNodes[index].hasFocus
                              ? colors.accent
                              : colors.border,
                          width: _focusNodes[index].hasFocus ? 1.5 : 1,
                        ),
                        boxShadow: CoolShadows.clay(
                          theme.brightness,
                          strength: 0.25,
                        ),
                      ),
                      child: TextField(
                        controller: _controllers[index],
                        focusNode: _focusNodes[index],
                        autofocus: widget.autofocus && index == 0,
                        enabled: widget.enabled,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        onChanged: (v) => _onChanged(index, v),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(widget.length),
                        ],
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colors.primaryText,
                          fontFamily: 'monospace',
                        ),
                        cursorColor: colors.accent,
                        decoration: const InputDecoration(
                          counterText: '',
                          border: InputBorder.none,
                          filled: true,
                          fillColor: Colors.transparent,
                          contentPadding: EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        if (hasError) ...[
          SizedBox(height: space.x2),
          Text(
            widget.error!,
            style: theme.textTheme.bodySmall?.copyWith(color: colors.danger),
          ),
        ],
      ],
    );
  }
}
