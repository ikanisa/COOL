import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';

/// A single-row widget displaying a group member with their avatar,
/// name / userId, admin badge (if applicable), and contribution amount.
///
/// Anonymous members show only the [userId] in DM Mono with a generic
/// gradient avatar.
class MemberRow extends StatelessWidget {
  const MemberRow({
    required this.userId,
    required this.contributionAmount,
    this.displayName,
    this.isAdmin = false,
    this.isAnonymous = false,
    super.key,
  });

  final String userId;
  final int contributionAmount;
  final String? displayName;
  final bool isAdmin;
  final bool isAnonymous;

  String get _initials {
    if (isAnonymous) return '?';
    if (displayName != null && displayName!.isNotEmpty) {
      final parts = displayName!.trim().split(' ');
      if (parts.length >= 2) {
        return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      }
      return parts[0].substring(0, (parts[0].length).clamp(0, 2)).toUpperCase();
    }
    return userId.substring(0, userId.length.clamp(0, 2)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          // ── Avatar ──────────────────────────────────────────────
          _Avatar(initials: _initials, isAnonymous: isAnonymous),
          const SizedBox(width: 12),

          // ── Name + ID ───────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Primary line
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isAnonymous ? userId : (displayName ?? userId),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: isAnonymous
                            ? GoogleFonts.dmMono(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.text2,
                              )
                            : GoogleFonts.dmSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.text,
                              ),
                      ),
                    ),
                    if (isAdmin) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accentGlow,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          'Admin',
                          style: GoogleFonts.dmSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                // Subtitle (userId) — only when we have a display name
                if (!isAnonymous && displayName != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    userId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: AppColors.text3,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Amount ──────────────────────────────────────────────
          Text(
            _formatAmount(contributionAmount),
            style: GoogleFonts.dmMono(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatAmount(int value) {
    final s = value.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

// ── Avatar ──────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials, required this.isAnonymous});
  final String initials;
  final bool isAnonymous;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isAnonymous ? AppColors.purpleGradient : null,
        color: isAnonymous ? null : AppColors.accentGlow,
        border: Border.all(color: AppColors.border2),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: GoogleFonts.dmSans(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: isAnonymous ? AppColors.purple : AppColors.accent,
        ),
      ),
    );
  }
}
