import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

/// A styled text field matching the COOL design system.
class CoolTextField extends StatelessWidget {
  const CoolTextField({
    required this.hint,
    this.label,
    this.controller,
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
  Widget build(BuildContext context) {
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final semanticsLabel = label ?? hint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Semantics(
            label: '${label!} field label',
            child: Text(
              label!,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.secondaryText,
              ),
            ),
          ),
          SizedBox(height: space.x2),
        ],
        Semantics(
          textField: true,
          label: semanticsLabel,
          hint: obscureText ? 'Secure entry field' : 'Double tap to enter text',
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radii.md),
              boxShadow: CoolShadows.clay(theme.brightness, strength: 0.45),
            ),
            child: TextFormField(
              controller: controller,
              keyboardType: keyboardType,
              obscureText: obscureText,
              validator: validator,
              maxLines: maxLines,
              onChanged: onChanged,
              autofocus: autofocus,
              textInputAction: textInputAction,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.primaryText,
              ),
              cursorColor: colors.accent,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: theme.inputDecorationTheme.hintStyle,
                filled: true,
                fillColor: colors.inputSurface,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: space.x5,
                  vertical: space.x5,
                ),
                prefixIcon: prefixIcon != null
                    ? Padding(
                        padding: EdgeInsets.only(
                          left: space.x4,
                          right: space.x2,
                        ),
                        child: Icon(
                          prefixIcon,
                          size: 20,
                          color: colors.secondaryText,
                        ),
                      )
                    : prefixEmoji != null
                    ? Padding(
                        padding: EdgeInsets.only(
                          left: space.x4,
                          right: space.x2,
                        ),
                        child: Text(
                          prefixEmoji!,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colors.primaryText,
                          ),
                        ),
                      )
                    : null,
                prefixIconConstraints:
                    (prefixIcon != null || prefixEmoji != null)
                    ? const BoxConstraints(minWidth: 0, minHeight: 0)
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(radii.md),
                  borderSide: BorderSide(color: colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(radii.md),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(radii.md),
                  borderSide: BorderSide(color: colors.accent, width: 1.6),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(radii.md),
                  borderSide: BorderSide(color: colors.danger),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(radii.md),
                  borderSide: BorderSide(color: colors.danger, width: 1.6),
                ),
                errorStyle: theme.inputDecorationTheme.errorStyle,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
