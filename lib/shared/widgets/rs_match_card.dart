import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/rs_colors.dart';
import '../../features/partners/rayon/models/rs_models.dart';

enum SelectedSeatType { general, vip }

extension SelectedSeatTypeX on SelectedSeatType {
  String get label => switch (this) {
    SelectedSeatType.general => 'General',
    SelectedSeatType.vip => 'VIP',
  };

  int priceFor(RsMatch match) => switch (this) {
    SelectedSeatType.general => match.ticketGeneralPrice,
    SelectedSeatType.vip => match.ticketVipPrice,
  };
}

class RsMatchCard extends StatefulWidget {
  const RsMatchCard({
    required this.match,
    required this.onBuyTap,
    this.isCompact = false,
    this.tierAccessible = true,
    this.selectedSeat,
    this.onSelectedSeatChanged,
    super.key,
  });

  final RsMatch match;
  final VoidCallback onBuyTap;
  final bool isCompact;
  final bool tierAccessible;
  final SelectedSeatType? selectedSeat;
  final ValueChanged<SelectedSeatType>? onSelectedSeatChanged;

  @override
  State<RsMatchCard> createState() => _RsMatchCardState();
}

class _RsMatchCardState extends State<RsMatchCard> {
  late SelectedSeatType _internalSeat;

  @override
  void initState() {
    super.initState();
    _internalSeat = widget.selectedSeat ?? SelectedSeatType.general;
  }

  @override
  void didUpdateWidget(covariant RsMatchCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedSeat != null &&
        widget.selectedSeat != oldWidget.selectedSeat) {
      _internalSeat = widget.selectedSeat!;
    }
  }

  void _selectSeat(SelectedSeatType seat) {
    widget.onSelectedSeatChanged?.call(seat);
    if (widget.selectedSeat == null) {
      setState(() => _internalSeat = seat);
    }
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    final effectiveSeat = widget.selectedSeat ?? _internalSeat;
    final cardRadius = BorderRadius.circular(18);
    final buttonEnabled =
        match.isOnSale && !match.isSoldOut && widget.tierAccessible;
    final buttonLabel = match.isSoldOut
        ? 'SOLD OUT'
        : !widget.tierAccessible
        ? 'EARLY ACCESS ONLY'
        : !match.isOnSale
        ? 'SALES CLOSED'
        : 'BUY TICKET';
    final cardPadding = widget.isCompact ? 16.0 : 18.0;
    final showRemainingChip =
        match.capacity > 0 &&
        !match.isSoldOut &&
        match.remainingCapacity < (match.capacity * 0.2);

    return Semantics(
      label: '${match.homeTeam} vs ${match.awayTeam}. '
          '${DateFormat('d MMM').format(match.matchDate)} at ${match.kickoffTime}. '
          '${match.venue}. $buttonLabel.',
      excludeSemantics: true,
      child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: cardRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: cardRadius,
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: RsColors.rsCardGradient,
            borderRadius: cardRadius,
            border: Border.all(color: AppColors.rsBlueBorder),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -36,
                right: -22,
                child: IgnorePointer(
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.rsBlueLight.withValues(alpha: 0.34),
                          AppColors.rsBlueGlow,
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(cardPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      match.competition.toUpperCase(),
                      style: GoogleFonts.barlow(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: AppColors.rsGoldLight,
                      ),
                    ),
                    SizedBox(height: widget.isCompact ? 10 : 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _TeamName(
                            name: match.homeTeam,
                            alignment: TextAlign.left,
                            isCompact: widget.isCompact,
                          ),
                        ),
                        SizedBox(width: widget.isCompact ? 8 : 12),
                        _VsBlock(
                          date: match.matchDate,
                          kickoffTime: match.kickoffTime,
                          isCompact: widget.isCompact,
                        ),
                        SizedBox(width: widget.isCompact ? 8 : 12),
                        Expanded(
                          child: _TeamName(
                            name: match.awayTeam,
                            alignment: TextAlign.right,
                            isCompact: widget.isCompact,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: widget.isCompact ? 12 : 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _DetailChip(
                          icon: Icons.place_outlined,
                          label: match.venue,
                        ),
                        _DetailChip(
                          icon: Icons.people_outline_rounded,
                          label: _capacityForVenue(match.venue),
                        ),
                        if (showRemainingChip)
                          _DetailChip(
                            icon: Icons.local_fire_department_rounded,
                            label: '${match.remainingCapacity} left',
                            highlight: true,
                          ),
                      ],
                    ),
                    SizedBox(height: widget.isCompact ? 14 : 16),
                    const _TicketTearDivider(),
                    SizedBox(height: widget.isCompact ? 14 : 16),
                    if (widget.isCompact)
                      _CompactFooter(
                        match: match,
                        seat: effectiveSeat,
                        onSeatSelected: _selectSeat,
                        onBuyTap: widget.onBuyTap,
                        enabled: buttonEnabled,
                        label: buttonLabel,
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: _PriceBlock(
                              price: effectiveSeat.priceFor(match),
                              seatLabel: effectiveSeat.label,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    _SeatTypeChip(
                                      label: SelectedSeatType.general.label,
                                      selected:
                                          effectiveSeat ==
                                          SelectedSeatType.general,
                                      onTap: () =>
                                          _selectSeat(SelectedSeatType.general),
                                    ),
                                    const SizedBox(width: 8),
                                    _SeatTypeChip(
                                      label: SelectedSeatType.vip.label,
                                      selected:
                                          effectiveSeat == SelectedSeatType.vip,
                                      onTap: () =>
                                          _selectSeat(SelectedSeatType.vip),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _BuyButton(
                                  enabled: buttonEnabled,
                                  onTap: widget.onBuyTap,
                                  label: buttonLabel,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _TeamName extends StatelessWidget {
  const _TeamName({
    required this.name,
    required this.alignment,
    required this.isCompact,
  });

  final String name;
  final TextAlign alignment;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return Text(
      name,
      textAlign: alignment,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.barlowCondensed(
        fontSize: isCompact ? 24 : 28,
        fontWeight: FontWeight.w900,
        color: AppColors.rsWhite,
        height: 0.95,
      ),
    );
  }
}

class _VsBlock extends StatelessWidget {
  const _VsBlock({
    required this.date,
    required this.kickoffTime,
    required this.isCompact,
  });

  final DateTime date;
  final String kickoffTime;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('d MMM').format(date).toUpperCase();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 10 : 12,
        vertical: isCompact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'VS',
            style: GoogleFonts.barlowCondensed(
              fontSize: isCompact ? 18 : 20,
              fontWeight: FontWeight.w700,
              color: AppColors.text3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$dateLabel\n$kickoffTime',
            textAlign: TextAlign.center,
            style: GoogleFonts.dmMono(
              fontSize: isCompact ? 10 : 11,
              fontWeight: FontWeight.w600,
              color: AppColors.rsBluePale,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({
    required this.icon,
    required this.label,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.rsGold.withValues(alpha: 0.16)
            : AppColors.surface.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight ? AppColors.rsGoldLight : AppColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: highlight ? AppColors.rsGoldLight : AppColors.rsBluePale,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.barlow(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: highlight
                    ? AppColors.rsGoldLight
                    : AppColors.rsWhite.withValues(alpha: 0.84),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketTearDivider extends StatelessWidget {
  const _TicketTearDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(child: CustomPaint(painter: _DashedLinePainter())),
          const Align(alignment: Alignment.centerLeft, child: _CutoutCircle()),
          const Align(alignment: Alignment.centerRight, child: _CutoutCircle()),
        ],
      ),
    );
  }
}

class _CutoutCircle extends StatelessWidget {
  const _CutoutCircle();

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, 0),
      child: Container(
        width: 16,
        height: 16,
        decoration: const BoxDecoration(
          color: AppColors.bg,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.rsBlueBorder.withValues(alpha: 0.8)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    const dashWidth = 6.0;
    const dashSpace = 5.0;
    final y = size.height / 2;
    double startX = 14;
    while (startX < size.width - 14) {
      canvas.drawLine(
        Offset(startX, y),
        Offset((startX + dashWidth).clamp(0, size.width), y),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PriceBlock extends StatelessWidget {
  const _PriceBlock({required this.price, required this.seatLabel});

  final int price;
  final String seatLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          seatLabel.toUpperCase(),
          style: GoogleFonts.barlow(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: AppColors.text2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _formatRwf(price),
          style: GoogleFonts.dmMono(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.rsGoldLight,
          ),
        ),
      ],
    );
  }
}

class _SeatTypeChip extends StatelessWidget {
  const _SeatTypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.rsBlue : AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.rsBlueBorder),
        ),
        child: Text(
          label,
          style: GoogleFonts.barlow(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.rsWhite : AppColors.text2,
          ),
        ),
      ),
    );
  }
}

class _BuyButton extends StatelessWidget {
  const _BuyButton({
    required this.enabled,
    required this.onTap,
    required this.label,
  });

  final bool enabled;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: enabled ? AppColors.rsBlue : AppColors.surface3,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(14),
            child: Center(
              child: Text(
                label,
                style: GoogleFonts.barlowCondensed(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: enabled ? AppColors.rsWhite : AppColors.text3,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactFooter extends StatelessWidget {
  const _CompactFooter({
    required this.match,
    required this.seat,
    required this.onSeatSelected,
    required this.onBuyTap,
    required this.enabled,
    required this.label,
  });

  final RsMatch match;
  final SelectedSeatType seat;
  final ValueChanged<SelectedSeatType> onSeatSelected;
  final VoidCallback onBuyTap;
  final bool enabled;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PriceBlock(price: seat.priceFor(match), seatLabel: seat.label),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _SeatTypeChip(
                label: SelectedSeatType.general.label,
                selected: seat == SelectedSeatType.general,
                onTap: () => onSeatSelected(SelectedSeatType.general),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SeatTypeChip(
                label: SelectedSeatType.vip.label,
                selected: seat == SelectedSeatType.vip,
                onTap: () => onSeatSelected(SelectedSeatType.vip),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _BuyButton(enabled: enabled, onTap: onBuyTap, label: label),
      ],
    );
  }
}

String _capacityForVenue(String venue) {
  final normalized = venue.toLowerCase();
  if (normalized.contains('kigali pele')) {
    return '18,000 cap';
  }
  if (normalized.contains('amahoro')) {
    return '45,000 cap';
  }
  if (normalized.contains('huye')) {
    return '12,000 cap';
  }
  if (normalized.contains('rubavu') || normalized.contains('umuganda')) {
    return '10,000 cap';
  }
  return '10,000 cap';
}

String _formatRwf(int amount) {
  return '${NumberFormat.decimalPattern('en').format(amount)} RWF';
}
