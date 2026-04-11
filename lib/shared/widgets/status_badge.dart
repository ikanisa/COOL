import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/cool_foundations.dart';

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
  const StatusBadge.saving({Key? key})
    : this._(
        label: null,
        bgColor: null,
        textColor: null,
        emoji: null,
        showPulseDot: false,
        tone: _StatusBadgeTone.saving,
        key: key,
      );

  /// Orange community preset.
  const StatusBadge.community({Key? key})
    : this._(
        label: null,
        bgColor: null,
        textColor: null,
        emoji: null,
        showPulseDot: false,
        tone: _StatusBadgeTone.community,
        key: key,
      );

  /// Blue public preset.
  const StatusBadge.public({Key? key})
    : this._(
        label: null,
        bgColor: null,
        textColor: null,
        emoji: null,
        showPulseDot: false,
        tone: _StatusBadgeTone.public,
        key: key,
      );

  /// Muted private preset.
  const StatusBadge.private({Key? key})
    : this._(
        label: null,
        bgColor: null,
        textColor: null,
        emoji: null,
        showPulseDot: false,
        tone: _StatusBadgeTone.private,
        key: key,
      );

  /// Online with animated pulse dot.
  const StatusBadge.online({Key? key})
    : this._(
        label: null,
        bgColor: null,
        textColor: null,
        emoji: null,
        showPulseDot: true,
        tone: _StatusBadgeTone.online,
        key: key,
      );

  /// Offline preset.
  const StatusBadge.offline({Key? key})
    : this._(
        label: null,
        bgColor: null,
        textColor: null,
        emoji: null,
        showPulseDot: false,
        tone: _StatusBadgeTone.offline,
        key: key,
      );

  final String? label;
  final Color? bgColor;
  final Color? textColor;
  final String? emoji;
  final bool showPulseDot;
  final _StatusBadgeTone? _tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final defaults = _colorsForTone(colors);
    final bg = bgColor ?? defaults.$1;
    final fg = textColor ?? defaults.$2;
    final resolvedLabel = _resolvedLabel(context);

    return Semantics(
      label: context.l10n.statusBadgeSemantics(resolvedLabel),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(CoolRadii.pill),
          border: Border.all(color: colors.border),
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
                child: Text(
                  emoji!,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1),
                ),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              resolvedLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: fg,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  (Color, Color) _colorsForTone(CoolSemanticColors colors) {
    return switch (_tone) {
      _StatusBadgeTone.community => (
        colors.warning.withValues(alpha: 0.12),
        colors.warning,
      ),
      _StatusBadgeTone.public => (
        colors.info.withValues(alpha: 0.10),
        colors.info,
      ),
      _StatusBadgeTone.private => (
        colors.cardSurfaceStrong,
        colors.secondaryText,
      ),
      _StatusBadgeTone.online => (
        colors.accent.withValues(alpha: 0.10),
        colors.accent,
      ),
      _StatusBadgeTone.offline => (
        colors.cardSurfaceStrong,
        colors.tertiaryText,
      ),
      _StatusBadgeTone.saving ||
      null => (colors.accent.withValues(alpha: 0.08), colors.accent),
    };
  }

  String _resolvedLabel(BuildContext context) {
    if (label != null) {
      return label!;
    }

    return switch (_tone) {
      _StatusBadgeTone.community => context.l10n.community,
      _StatusBadgeTone.public => context.l10n.public,
      _StatusBadgeTone.private => context.l10n.private,
      _StatusBadgeTone.online => context.l10n.online,
      _StatusBadgeTone.offline => context.l10n.offline,
      _StatusBadgeTone.saving || null => context.l10n.saving,
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
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
