import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

/// A styled text field matching the COOL design system.
class CoolTextField extends StatefulWidget {
  const CoolTextField({
    required this.hint,
    this.label,
    this.controller,
    this.focusNode,
    this.keyboardType,
    this.prefixEmoji,
    this.prefixIcon,
    this.obscureText = false,
    this.validator,
    this.maxLines = 1,
    this.onChanged,
    this.autofocus = false,
    this.textInputAction,
    super.key,
  });

  final String hint;
  final String? label;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final String? prefixEmoji;
  final IconData? prefixIcon;
  final bool obscureText;
  final String? Function(String?)? validator;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final TextInputAction? textInputAction;

  @override
  State<CoolTextField> createState() => _CoolTextFieldState();
}

class _CoolTextFieldState extends State<CoolTextField> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    const fieldRadius = 14.0;
    final semanticsLabel = widget.label ?? widget.hint;
    final fieldBackground = _isFocused
        ? colors.cardSurfaceStrong
        : colors.inputSurface;
    final fieldShadow = _isFocused
        ? CoolShadows.clay(theme.brightness, strength: 0.58)
        : CoolShadows.clay(theme.brightness, strength: 0.38);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Semantics(
            label: '${widget.label!} field label',
            child: Text(
              widget.label!,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: _isFocused
                    ? colors.buttonPrimaryBackground
                    : colors.secondaryText,
              ),
            ),
          ),
          SizedBox(height: space.x2),
        ],
        Semantics(
          textField: true,
          label: semanticsLabel,
          hint: widget.obscureText
              ? 'Secure entry field'
              : 'Double tap to enter text',
          child: AnimatedContainer(
            duration: CoolMotion.standard,
            curve: CoolMotion.enterCurve,
            decoration: BoxDecoration(
              color: fieldBackground,
              borderRadius: BorderRadius.circular(fieldRadius),
              border: _isFocused
                  ? Border.all(
                      color: colors.buttonPrimaryBackground.withValues(
                        alpha: 0.18,
                      ),
                    )
                  : null,
              boxShadow: fieldShadow,
            ),
            child: Focus(
              onFocusChange: (value) {
                if (_isFocused != value) {
                  setState(() => _isFocused = value);
                }
              },
              child: TextFormField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                keyboardType: widget.keyboardType,
                obscureText: widget.obscureText,
                validator: widget.validator,
                maxLines: widget.maxLines,
                onChanged: widget.onChanged,
                autofocus: widget.autofocus,
                textInputAction: widget.textInputAction,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.primaryText,
                ),
                cursorColor: colors.buttonPrimaryBackground,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: theme.inputDecorationTheme.hintStyle,
                  filled: false,
                  fillColor: Colors.transparent,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: space.x5,
                    vertical: space.x5,
                  ),
                  prefixIcon: widget.prefixIcon != null
                      ? Padding(
                          padding: EdgeInsets.only(
                            left: space.x4,
                            right: space.x2,
                          ),
                          child: Icon(
                            widget.prefixIcon,
                            size: 20,
                            color: _isFocused
                                ? colors.buttonPrimaryBackground
                                : colors.secondaryText,
                          ),
                        )
                      : widget.prefixEmoji != null
                      ? Padding(
                          padding: EdgeInsets.only(
                            left: space.x4,
                            right: space.x2,
                          ),
                          child: Text(
                            widget.prefixEmoji!,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: colors.primaryText,
                            ),
                          ),
                        )
                      : null,
                  prefixIconConstraints:
                      (widget.prefixIcon != null || widget.prefixEmoji != null)
                      ? const BoxConstraints(minWidth: 0, minHeight: 0)
                      : null,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  errorStyle: theme.inputDecorationTheme.errorStyle,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
