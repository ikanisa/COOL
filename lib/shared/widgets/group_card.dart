import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/cool_palette.dart';
import 'status_badge.dart';

/// A horizontally-scrollable group card showing type, amount, progress,
/// and a member avatar stack.
///
/// Designed for use inside a horizontal [ListView] — has a fixed min
/// width of 200 and expands as needed.
class GroupCard extends StatelessWidget {
  const GroupCard({
    required this.name,
    required this.type,
    required this.visibility,
    required this.amount,
    required this.memberCount,
    required this.targetAmount,
    required this.onTap,
    super.key,
  });

  final String name;

  /// Either `'saving'` or `'community'`.
  final String type;

  /// Either `'public'` or `'private'`.
  final String visibility;

  final int amount;
  final int memberCount;
  final int targetAmount;
  final VoidCallback onTap;

  bool get _isSaving => type == 'saving';

  Color _accentColor(CoolPalette palette) => _isSaving ? palette.accent : palette.orange;

  double get _progress =>
      targetAmount > 0 ? (amount / targetAmount).clamp(0.0, 1.0) : 0.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final accent = _accentColor(palette);
    return Semantics(
      button: true,
      label:
          '$name. ${_isSaving ?'Saving' : 'Community'} group. '
          '${GroupCard._formatAmount(amount)} RWF. $memberCount members.',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 200),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: palette.surface2,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Badges ────────────────────────────────────────────────
              Row(
                children: [
                  if (_isSaving) const StatusBadge.saving() else const StatusBadge.community(),
                  const SizedBox(width: 6),
                  if (visibility == 'public') const StatusBadge.public() else const StatusBadge.private(),
                ],
              ),
              const SizedBox(height: 12),

              // ── Name ──────────────────────────────────────────────────
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: palette.text,
                ),
              ),
              const SizedBox(height: 8),

              // ── Amount ────────────────────────────────────────────────
              Text(
                '${_formatAmount(amount)} RWF',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmMono(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
              const SizedBox(height: 12),

              // ── Progress bar ──────────────────────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 4,
                  backgroundColor: palette.surface3,
                  color: accent,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Target: ${_formatAmount(targetAmount)} RWF',
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: palette.text3,
                ),
              ),
              const SizedBox(height: 12),

              // ── Member stack ──────────────────────────────────────────
              _MemberAvatarStack(
                memberCount: memberCount,
                accentColor: accent,
                palette: palette,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatAmount(int value) {
    // Simple thousands grouping (e.g. 1,200,000).
    final s = value.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

// ── Member avatar stack ─────────────────────────────────────────────────

class _MemberAvatarStack extends StatelessWidget {
  const _MemberAvatarStack({
    required this.memberCount,
    required this.accentColor,
    required this.palette,
  });

  final int memberCount;
  final Color accentColor;
  final CoolPalette palette;

  static const _size = 28.0;
  static const _overlap = 10.0;
  static const _maxVisible = 3;
  static const _initials = ['A', 'B', 'C'];

  @override
  Widget build(BuildContext context) {
    final visibleCount = memberCount.clamp(0, _maxVisible);
    final overflow = memberCount - _maxVisible;

    return SizedBox(
      height: _size,
      child: Row(
        children: [
          // Stacked avatars
          SizedBox(
            width: visibleCount > 0
                ? _size + (_overlap * (visibleCount - 1).clamp(0, _maxVisible))
                : 0,
            child: Stack(
              children: List.generate(visibleCount, (i) {
                return Positioned(
                  left: i * _overlap,
                  child: Container(
                    width: _size,
                    height: _size,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: palette.surface2, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _initials[i],
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: accentColor,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          if (overflow > 0) ...[
            const SizedBox(width: 6),
            Text(
              '+$overflow',
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: palette.text3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
