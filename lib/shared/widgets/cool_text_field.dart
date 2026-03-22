import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/cool_foundations.dart';
import '../../core/theme/cool_palette.dart';

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
    final theme = Theme.of(context);
    final palette = context.coolPalette;
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
              style:
                  theme.textTheme.labelLarge?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: colors.secondaryText,
                  ) ??
                  GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: colors.secondaryText,
                  ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Semantics(
          textField: true,
          label: semanticsLabel,
          hint: obscureText ? 'Secure entry field' : 'Double tap to enter text',
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(CoolRadii.md),
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
              style:
                  theme.textTheme.titleSmall?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: colors.primaryText,
                  ) ??
                  GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: colors.primaryText,
                  ),
              cursorColor: colors.accent,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: theme.inputDecorationTheme.hintStyle,
                filled: true,
                fillColor: colors.inputSurface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 20,
                ),
                prefixIcon: prefixIcon != null
                    ? Padding(
                        padding: const EdgeInsets.only(left: 18, right: 10),
                        child: Icon(
                          prefixIcon,
                          size: 20,
                          color: colors.secondaryText,
                        ),
                      )
                    : prefixEmoji != null
                    ? Padding(
                        padding: const EdgeInsets.only(left: 18, right: 10),
                        child: Text(
                          prefixEmoji!,
                          style: const TextStyle(fontSize: 20),
                        ),
                      )
                    : null,
                prefixIconConstraints:
                    (prefixIcon != null || prefixEmoji != null)
                    ? const BoxConstraints(minWidth: 0, minHeight: 0)
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CoolRadii.md),
                  borderSide: BorderSide(color: colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CoolRadii.md),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CoolRadii.md),
                  borderSide: BorderSide(color: colors.accent, width: 1.6),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CoolRadii.md),
                  borderSide: BorderSide(color: palette.red),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CoolRadii.md),
                  borderSide: BorderSide(color: palette.red, width: 1.6),
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
