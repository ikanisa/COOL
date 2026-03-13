import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';

/// A styled text field matching the Cool design system.
///
/// Includes an optional label above the field, a prefix icon or emoji
/// inside the field, and validation support.
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
    final semanticsLabel = label ?? hint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Label ─────────────────────────────────────────────────
        if (label != null) ...[
          Semantics(
            label: '${label!} field label',
            child: Text(
              label!,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.text2,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],

        // ── Field ─────────────────────────────────────────────────
        Semantics(
          textField: true,
          label: semanticsLabel,
          hint: obscureText ? 'Secure entry field' : 'Double tap to enter text',
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            obscureText: obscureText,
            validator: validator,
            maxLines: maxLines,
            onChanged: onChanged,
            autofocus: autofocus,
            textInputAction: textInputAction,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppColors.text,
            ),
            cursorColor: AppColors.accent,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.dmSans(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: AppColors.text3,
              ),
              filled: true,
              fillColor: AppColors.surface2,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 16,
              ),
              prefixIcon: prefixIcon != null
                  ? Padding(
                      padding: const EdgeInsets.only(left: 16, right: 8),
                      child: Icon(prefixIcon, size: 18, color: AppColors.text2),
                    )
                  : prefixEmoji != null
                  ? Padding(
                      padding: const EdgeInsets.only(left: 16, right: 8),
                      child: Text(
                        prefixEmoji!,
                        style: const TextStyle(fontSize: 18),
                      ),
                    )
                  : null,
              prefixIconConstraints:
                  (prefixIcon != null || prefixEmoji != null)
                  ? const BoxConstraints(minWidth: 0, minHeight: 0)
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppColors.accent,
                  width: 1.5,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.red),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.red, width: 1.5),
              ),
              errorStyle: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: AppColors.red,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
