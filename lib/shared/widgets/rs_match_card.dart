import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/cool_foundations.dart';
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
    final theme = Theme.of(context);
    final match = widget.match;
    final effectiveSeat = widget.selectedSeat ?? _internalSeat;
    final cardRadius = BorderRadius.circular(widget.isCompact ? 24 : 28);
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
    final statusLabel = match.isSoldOut
        ? 'SOLD OUT'
        : !widget.tierAccessible && match.isOnSale
        ? 'TIER ACCESS'
        : match.isOnSale
        ? 'ON SALE'
        : 'UPCOMING';
    final statusBackground = match.isSoldOut
        ? AppColors.red.withValues(alpha: 0.18)
        : !widget.tierAccessible && match.isOnSale
        ? AppColors.rsGold.withValues(alpha: 0.16)
        : match.isOnSale
        ? AppColors.accent.withValues(alpha: 0.18)
        : AppColors.rsBlue.withValues(alpha: 0.14);
    final statusForeground = match.isSoldOut
        ? const Color(0xFFFFC0C5)
        : !widget.tierAccessible && match.isOnSale
        ? AppColors.rsGoldLight
        : AppColors.rsWhite;

    return Semantics(
      label:
          '${match.homeTeam} vs ${match.awayTeam}.'
          '${DateFormat('d MMM').format(match.matchDate)} at ${match.kickoffTime}. '
          '${match.venue}. $buttonLabel.',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: cardRadius,
          boxShadow: CoolShadows.clay(theme.brightness, strength: 0.42),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: cardRadius,
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: cardRadius,
              border: Border.all(color: AppColors.rsBlueBorder),
            ),
            child: Padding(
              padding: EdgeInsets.all(cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          match.competition.toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                            color: AppColors.rsGoldLight,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _MatchStatusBadge(
                        label: statusLabel,
                        backgroundColor: statusBackground,
                        foregroundColor: statusForeground,
                      ),
                    ],
                  ),
                  SizedBox(height: widget.isCompact ? 10 : 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _TeamPanel(
                          name: match.homeTeam,
                          alignment: CrossAxisAlignment.start,
                          sideLabel: 'HOME',
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
                        child: _TeamPanel(
                          name: match.awayTeam,
                          alignment: CrossAxisAlignment.end,
                          sideLabel: 'AWAY',
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
                      _DetailChip(
                        icon: Icons.sell_outlined,
                        label: _ticketingMeta(match, widget.tierAccessible),
                        highlight: match.isOnSale && !match.isSoldOut,
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
          ),
        ),
      ),
    );
  }
}

class _TeamPanel extends StatelessWidget {
  const _TeamPanel({
    required this.name,
    required this.alignment,
    required this.sideLabel,
    required this.isCompact,
  });

  final String name;
  final CrossAxisAlignment alignment;
  final String sideLabel;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final abbreviation = _teamAbbreviation(name);

    return Column(
      crossAxisAlignment: alignment,
      children: [
        Container(
          width: isCompact ? 40 : 46,
          height: isCompact ? 40 : 46,
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          alignment: Alignment.center,
          child: Text(
            abbreviation,
            style: theme.textTheme.labelLarge?.copyWith(
              fontSize: isCompact ? 14 : 15,
              fontWeight: FontWeight.w800,
              color: AppColors.rsWhite,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          sideLabel,
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: AppColors.text3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          name,
          textAlign: alignment == CrossAxisAlignment.end
              ? TextAlign.right
              : TextAlign.left,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontSize: isCompact ? 24 : 28,
            fontWeight: FontWeight.w800,
            color: AppColors.rsWhite,
            height: 0.95,
          ),
        ),
      ],
    );
  }
}

class _MatchStatusBadge extends StatelessWidget {
  const _MatchStatusBadge({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
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
        border: Border.all(color: foregroundColor.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: foregroundColor,
        ),
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
    final theme = Theme.of(context);
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
            style: theme.textTheme.labelLarge?.copyWith(
              fontSize: isCompact ? 16 : 18,
              fontWeight: FontWeight.w800,
              color: AppColors.text3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$dateLabel $kickoffTime',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: isCompact ? 14 : 15,
              fontWeight: FontWeight.w700,
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
    final theme = Theme.of(context);
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
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w700,
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
        decoration: BoxDecoration(color: AppColors.bg, shape: BoxShape.circle),
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
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          seatLabel.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            color: AppColors.text2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _formatRwf(price),
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w800,
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
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.rsBlue : AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.rsBlueBorder),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w800,
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
    final theme = Theme.of(context);
    return SizedBox(
      height: 52,
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
                style: theme.textTheme.labelLarge?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: enabled ? AppColors.rsWhite : AppColors.text3,
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

String _ticketingMeta(RsMatch match, bool tierAccessible) {
  if (match.isSoldOut) {
    return 'Allocation exhausted';
  }
  if (!tierAccessible && match.isOnSale) {
    return 'Tier priority';
  }
  if (match.isOnSale) {
    return 'Digital entry live';
  }
  return 'Ticketing opens soon';
}

String _teamAbbreviation(String name) {
  final parts = name
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) {
    return 'FC';
  }
  if (parts.length == 1) {
    final value = parts.first;
    return value.length >= 3
        ? value.substring(0, 3).toUpperCase()
        : value.toUpperCase();
  }

  final buffer = StringBuffer();
  for (final part in parts.take(3)) {
    buffer.write(part[0].toUpperCase());
  }
  return buffer.toString();
}

String _formatRwf(int amount) {
  return '${NumberFormat.decimalPattern('en').format(amount)} RWF';
}
