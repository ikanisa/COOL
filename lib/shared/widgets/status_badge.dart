import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/cool_palette.dart';


/// A small pill badge used to indicate status, category, or role.
///
/// Use the default constructor for custom colours, or one of the
/// named constructors for design-system presets.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    required this.label,
    this.bgColor,
    this.textColor,
    this.emoji,
    super.key,
  }) : showPulseDot = false,
       _tone = null;

  const StatusBadge._({
    required this.label,
    this.bgColor,
    this.textColor,
    this.emoji,
    required this.showPulseDot,
    required _StatusBadgeTone tone,
    super.key,
  }) : _tone = tone;

  // ── Preset constructors ─────────────────────────────────────────────

  /// Green saving preset.
  StatusBadge.saving({Key? key})
    : this._(
        label: 'Saving',
        bgColor: null,
        textColor: null,
        emoji: null,
        showPulseDot: false,
        tone: _StatusBadgeTone.saving,
        key: key,
      );

  /// Orange community preset.
  StatusBadge.community({Key? key})
    : this._(
        label: 'Community',
        bgColor: null,
        textColor: null,
        emoji: null,
        showPulseDot: false,
        tone: _StatusBadgeTone.community,
        key: key,
      );

  /// Blue public preset.
  StatusBadge.public({Key? key})
    : this._(
        label: 'Public',
        bgColor: null,
        textColor: null,
        emoji: null,
        showPulseDot: false,
        tone: _StatusBadgeTone.public,
        key: key,
      );

  /// Muted private preset.
  StatusBadge.private({Key? key})
    : this._(
        label: 'Private',
        bgColor: null,
        textColor: null,
        emoji: null,
        showPulseDot: false,
        tone: _StatusBadgeTone.private,
        key: key,
      );

  /// Online with animated pulse dot.
  StatusBadge.online({Key? key})
    : this._(
        label: 'Online',
        bgColor: null,
        textColor: null,
        emoji: null,
        showPulseDot: true,
        tone: _StatusBadgeTone.online,
        key: key,
      );

  /// Offline preset.
  StatusBadge.offline({Key? key})
    : this._(
        label: 'Offline',
        bgColor: null,
        textColor: null,
        emoji: null,
        showPulseDot: false,
        tone: _StatusBadgeTone.offline,
        key: key,
      );

  final String label;
  final Color? bgColor;
  final Color? textColor;
  final String? emoji;
  final bool showPulseDot;
  final _StatusBadgeTone? _tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final defaults = _colorsForTone(palette);
    final bg = bgColor ?? defaults.$1;
    final fg = textColor ?? defaults.$2;

    return Semantics(
      label: 'Status: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showPulseDot) ...[
              _PulseDot(color: fg),
              const SizedBox(width: 6),
            ],
            if (emoji != null) ...[
              ExcludeSemantics(
                child: Text(emoji!, style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: fg,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  (Color, Color) _colorsForTone(CoolPalette palette) {
    return switch (_tone) {
      _StatusBadgeTone.community => (
        AppColors.orange.withValues(alpha: 0.15),
        palette.orange,
      ),
      _StatusBadgeTone.public => (palette.blueGlow, palette.blue),
      _StatusBadgeTone.private => (palette.surface3, palette.text2),
      _StatusBadgeTone.online => (palette.accentGlow, palette.accent),
      _StatusBadgeTone.offline => (palette.surface3, palette.text3),
      _StatusBadgeTone.saving || null => (palette.accentGlow, palette.accent),
    };
  }
}

enum _StatusBadgeTone { saving, community, public, private, online, offline }

// ── Animated pulse dot ──────────────────────────────────────────────────

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color});
  final Color color;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _animation = Tween<double>(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}