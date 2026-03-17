import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';

/// Shared helper widgets and functions for the Bank Admin screens.

// ── Formatting helpers ──────────────────────────────────────────

String bankTitle(String raw) {
  if (raw.trim().isEmpty) return '-';
  return raw
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String bankFileSafe(String raw) {
  return raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

// ── Shared widgets ──────────────────────────────────────────────

class BankInfoPill extends StatelessWidget {
  const BankInfoPill({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label: $value',
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.text2,
        ),
      ),
    );
  }
}

class BankStatusTag extends StatelessWidget {
  const BankStatusTag({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    super.key,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: foregroundColor,
        ),
      ),
    );
  }
}

Color bankLoanStatusColor(String status) {
  switch (status) {
    case 'approved':
    case 'completed':
      return Colors.green;
    case 'disbursed':
    case 'repaying':
      return Colors.blue;
    case 'defaulted':
      return Colors.red;
    case 'rejected':
      return Colors.orange;
    default:
      return Colors.grey;
  }
}
