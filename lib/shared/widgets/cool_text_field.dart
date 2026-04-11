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
    this.autofillHints,
    this.enableSuggestions = true,
    this.autocorrect = true,
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

  /// Web-specific autofill hints for browser autocomplete.
  ///
  /// Maps to HTML `autocomplete` attribute. Example values:
  /// - [AutofillHints.email] → `autocomplete="email"`
  /// - [AutofillHints.name] → `autocomplete="name"`
  /// - [AutofillHints.telephoneNumber] → `autocomplete="tel"`
  /// - [AutofillHints.password] → `autocomplete="current-password"`
  final Iterable<String>? autofillHints;

  /// Whether to show keyboard suggestions.
  final bool enableSuggestions;

  /// Whether to enable autocorrect.
  final bool autocorrect;

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
    const fieldRadius = CoolRadii.md;
    final semanticsLabel = widget.label ?? widget.hint;
    final fieldBackground = _isFocused
        ? colors.cardSurfaceStrong
        : colors.inputSurface;
    // Tactile Monolith: "sunken" input — simulated inner shadows
    // via close, negative-spread outer shadows + top highlight inversion.
    final fieldShadow = <BoxShadow>[
      // Inner depth: dark top edge simulates being recessed
      BoxShadow(
        color: colors.shadowColor.withValues(alpha: _isFocused ? 0.38 : 0.24),
        blurRadius: 6,
        spreadRadius: -2,
        offset: const Offset(0, 2),
      ),
      // Subtle bottom highlight edge: simulates light hitting the lower lip
      BoxShadow(
        color: colors.highlightColor.withValues(
          alpha: _isFocused ? 0.32 : 0.14,
        ),
        blurRadius: 0,
        offset: const Offset(0, -1),
      ),
    ];

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
                fontWeight: FontWeight.w700,
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
                  ? Border.all(color: colors.accentDeep.withValues(alpha: 0.40))
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
                autofillHints: widget.autofillHints,
                enableSuggestions: widget.enableSuggestions,
                autocorrect: widget.autocorrect,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
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
