import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/identity/public_user_identity.dart';
import '../../core/theme/cool_palette.dart';

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
    final identity = PublicUserIdentity.resolve(
      publicUserId: displayName,
      userId: userId,
    );
    return identity.substring(0, 2);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final resolvedIdentity = PublicUserIdentity.resolve(
      publicUserId: displayName,
      userId: userId,
    );
    final name = isAnonymous ? resolvedIdentity : resolvedIdentity;
    final roleLabel = isAdmin ? ' Admin.' : '';

    return RepaintBoundary(
      child: Semantics(
      label:
          '$name.$roleLabel'
          '${MemberRow._formatAmount(contributionAmount)} RWF contributed.',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            // ── Avatar ──────────────────────────────────────────────
            _Avatar(initials: _initials, isAnonymous: isAnonymous, palette: palette),
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
                          resolvedIdentity,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: isAnonymous
                              ? GoogleFonts.dmMono(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: palette.text2,
                                )
                              : GoogleFonts.dmSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: palette.text,
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
                            color: palette.accentGlow,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text(
                            'Admin',
                            style: GoogleFonts.dmSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: palette.accent,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // ── Amount ──────────────────────────────────────────────
            Text(
              _formatAmount(contributionAmount),
              style: GoogleFonts.dmMono(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: palette.accent,
              ),
            ),
          ],
        ),
        ),
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
  const _Avatar({required this.initials, required this.isAnonymous, required this.palette});
  final String initials;
  final bool isAnonymous;
  final CoolPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isAnonymous ? LinearGradient(colors: [palette.purple, palette.purple.withValues(alpha: 0.6)]) : null,
        color: isAnonymous ? null : palette.accentGlow,
        border: Border.all(color: palette.border2),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: GoogleFonts.dmSans(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: isAnonymous ? palette.purple : palette.accent,
        ),
      ),
    );
  }
}
