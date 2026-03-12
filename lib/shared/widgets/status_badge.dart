import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';

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
  }) : showPulseDot = false;

  const StatusBadge._({
    required this.label,
    this.bgColor,
    this.textColor,
    this.emoji,
    required this.showPulseDot,
    super.key,
  });

  // ── Preset constructors ─────────────────────────────────────────────

  /// Green saving preset.
  const StatusBadge.saving({Key? key})
    : this._(
        label: 'Saving',
        bgColor: AppColors.accentGlow,
        textColor: AppColors.accent,
        emoji: null,
        showPulseDot: false,
        key: key,
      );

  /// Orange community preset.
  const StatusBadge.community({Key? key})
    : this._(
        label: 'Community',
        bgColor: const Color(0x26FF6B35),
        textColor: AppColors.orange,
        emoji: null,
        showPulseDot: false,
        key: key,
      );

  /// Blue public preset.
  const StatusBadge.public({Key? key})
    : this._(
        label: 'Public',
        bgColor: AppColors.blueGlow,
        textColor: AppColors.blue,
        emoji: null,
        showPulseDot: false,
        key: key,
      );

  /// Muted private preset.
  const StatusBadge.private({Key? key})
    : this._(
        label: 'Private',
        bgColor: AppColors.surface3,
        textColor: AppColors.text2,
        emoji: null,
        showPulseDot: false,
        key: key,
      );

  /// Online with animated pulse dot.
  const StatusBadge.online({Key? key})
    : this._(
        label: 'Online',
        bgColor: AppColors.accentGlow,
        textColor: AppColors.accent,
        emoji: null,
        showPulseDot: true,
        key: key,
      );

  /// Offline preset.
  const StatusBadge.offline({Key? key})
    : this._(
        label: 'Offline',
        bgColor: AppColors.surface3,
        textColor: AppColors.text3,
        emoji: null,
        showPulseDot: false,
        key: key,
      );

  final String label;
  final Color? bgColor;
  final Color? textColor;
  final String? emoji;
  final bool showPulseDot;

  @override
  Widget build(BuildContext context) {
    final bg = bgColor ?? AppColors.accentGlow;
    final fg = textColor ?? AppColors.accent;

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
            if (showPulseDot) ...[_PulseDot(color: fg), const SizedBox(width: 6)],
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
}

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
