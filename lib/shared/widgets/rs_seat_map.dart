

import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';
import '../../core/theme/rs_colors.dart';
import 'rs_match_card.dart';

/// A simplified stadium zone picker for Amahoro Stadium.
///
/// Renders a stylised bird's-eye stadium overview with two selectable zones:
/// **General** (curved stands) and **VIP** (central section).
/// Tapping a zone fires [onZoneSelected] with the corresponding
/// [SelectedSeatType].
///
/// Usage:
/// ```dart
/// RsSeatMap(
///   selected: SelectedSeatType.general,
///   onZoneSelected: (zone) => setState(() => _zone = zone),
/// )
/// ```
class RsSeatMap extends StatelessWidget {
  const RsSeatMap({
    required this.selected,
    required this.onZoneSelected,
    this.height = 200,
    super.key,
  });

  final SelectedSeatType selected;
  final ValueChanged<SelectedSeatType> onZoneSelected;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(CoolRadii.lg),
        border: Border.all(color: colors.borderStrong),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Icon(Icons.stadium_rounded, size: 16, color: colors.secondaryText),
                const SizedBox(width: 8),
                Text(
                  'AMAHORO STADIUM',
                  style: GoogleFonts.dmMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: colors.secondaryText,
                    letterSpacing: 1.0,
                  ),
                ),
                const Spacer(),
                const _LegendDot(color: RsColors.rsGold, label: 'Selected'),
                const SizedBox(width: 12),
                const _LegendDot(color: Color(0x805A7DAE), label: 'Available'),
              ],
            ),
          ),
          // Stadium map
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: CustomPaint(
                painter: _StadiumPainter(
                  selected: selected,
                  generalColor: selected == SelectedSeatType.general
                      ? RsColors.rsGold.withValues(alpha: 0.85)
                      : RsColors.rsNavyLight.withValues(alpha: 0.25),
                  vipColor: selected == SelectedSeatType.vip
                      ? RsColors.rsGold.withValues(alpha: 0.85)
                      : RsColors.rsNavyLight.withValues(alpha: 0.25),
                  lineColor: colors.borderStrong,
                  fieldColor: const Color(0xFF1B4332),
                ),
                child: SizedBox.expand(
                  child: Stack(
                    children: [
                      // General zone tap targets (top + bottom stands)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: height * 0.28,
                        child: GestureDetector(
                          onTap: () => onZoneSelected(SelectedSeatType.general),
                          behavior: HitTestBehavior.opaque,
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: height * 0.28,
                        child: GestureDetector(
                          onTap: () => onZoneSelected(SelectedSeatType.general),
                          behavior: HitTestBehavior.opaque,
                        ),
                      ),
                      // VIP zone tap target (center)
                      Center(
                        child: GestureDetector(
                          onTap: () => onZoneSelected(SelectedSeatType.vip),
                          behavior: HitTestBehavior.opaque,
                          child: SizedBox(
                            width: 120,
                            height: height * 0.22,
                          ),
                        ),
                      ),
                      // Zone labels
                      Positioned(
                        top: 8,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: _ZoneLabel(
                            label: 'GENERAL',
                            isSelected: selected == SelectedSeatType.general,
                          ),
                        ),
                      ),
                      Center(
                        child: _ZoneLabel(
                          label: 'VIP',
                          isSelected: selected == SelectedSeatType.vip,
                        ),
                      ),
                      Positioned(
                        bottom: 8,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: _ZoneLabel(
                            label: 'GENERAL',
                            isSelected: selected == SelectedSeatType.general,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoneLabel extends StatelessWidget {
  const _ZoneLabel({required this.label, required this.isSelected});

  final String label;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected
            ? RsColors.rsGold.withValues(alpha: 0.2)
            : Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(CoolRadii.pill),
        border: Border.all(
          color: isSelected
              ? RsColors.rsGold.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.15),
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmMono(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: isSelected ? RsColors.rsGoldLight : Colors.white54,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.dmMono(
            fontSize: 8,
            fontWeight: FontWeight.w600,
            color: Colors.white54,
          ),
        ),
      ],
    );
  }
}

/// Paints a simplified bird's-eye stadium with curved stands and a
/// central pitch rectangle.
class _StadiumPainter extends CustomPainter {
  _StadiumPainter({
    required this.selected,
    required this.generalColor,
    required this.vipColor,
    required this.lineColor,
    required this.fieldColor,
  });

  final SelectedSeatType selected;
  final Color generalColor;
  final Color vipColor;
  final Color lineColor;
  final Color fieldColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    // ── Pitch (green rectangle) ────────────────
    final pitchRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy), width: w * 0.6, height: h * 0.38),
      const Radius.circular(6),
    );
    canvas.drawRRect(pitchRect, Paint()..color = fieldColor);

    // Pitch outline
    canvas.drawRRect(
      pitchRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Center circle
    canvas.drawCircle(
      Offset(cx, cy),
      h * 0.08,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Center dot
    canvas.drawCircle(
      Offset(cx, cy),
      2,
      Paint()..color = Colors.white.withValues(alpha: 0.3),
    );

    // ── Top stand (General) ────────────────────
    final topStandPath = Path()
      ..moveTo(w * 0.08, h * 0.28)
      ..quadraticBezierTo(cx, h * 0.02, w * 0.92, h * 0.28)
      ..lineTo(w * 0.82, h * 0.32)
      ..quadraticBezierTo(cx, h * 0.12, w * 0.18, h * 0.32)
      ..close();
    canvas.drawPath(topStandPath, Paint()..color = generalColor);
    canvas.drawPath(
      topStandPath,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    // ── Bottom stand (General) ─────────────────
    final bottomStandPath = Path()
      ..moveTo(w * 0.08, h * 0.72)
      ..quadraticBezierTo(cx, h * 0.98, w * 0.92, h * 0.72)
      ..lineTo(w * 0.82, h * 0.68)
      ..quadraticBezierTo(cx, h * 0.88, w * 0.18, h * 0.68)
      ..close();
    canvas.drawPath(bottomStandPath, Paint()..color = generalColor);
    canvas.drawPath(
      bottomStandPath,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    // ── Left stand (General) ───────────────────
    final leftStandPath = Path()
      ..moveTo(w * 0.08, h * 0.28)
      ..quadraticBezierTo(w * 0.0, cy, w * 0.08, h * 0.72)
      ..lineTo(w * 0.14, h * 0.65)
      ..quadraticBezierTo(w * 0.08, cy, w * 0.14, h * 0.35)
      ..close();
    canvas.drawPath(leftStandPath, Paint()..color = generalColor);
    canvas.drawPath(
      leftStandPath,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    // ── Right stand (General) ──────────────────
    final rightStandPath = Path()
      ..moveTo(w * 0.92, h * 0.28)
      ..quadraticBezierTo(w, cy, w * 0.92, h * 0.72)
      ..lineTo(w * 0.86, h * 0.65)
      ..quadraticBezierTo(w * 0.92, cy, w * 0.86, h * 0.35)
      ..close();
    canvas.drawPath(rightStandPath, Paint()..color = generalColor);
    canvas.drawPath(
      rightStandPath,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    // ── VIP Box (center of top stand) ──────────
    final vipW = w * 0.24;
    final vipH = h * 0.10;
    final vipRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy), width: vipW, height: vipH),
      const Radius.circular(4),
    );
    canvas.drawRRect(vipRect, Paint()..color = vipColor);
    canvas.drawRRect(
      vipRect,
      Paint()
        ..color = RsColors.rsGold.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_StadiumPainter oldDelegate) =>
      selected != oldDelegate.selected ||
      generalColor != oldDelegate.generalColor ||
      vipColor != oldDelegate.vipColor;
}
