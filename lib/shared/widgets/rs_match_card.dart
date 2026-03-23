import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/cool_foundations.dart';
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
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final theme = Theme.of(context);
    final match = widget.match;
    final effectiveSeat = widget.selectedSeat ?? _internalSeat;
    final cardRadius = BorderRadius.circular(
      widget.isCompact ? radii.md : radii.lg,
    );
    final buttonEnabled =
        match.isOnSale && !match.isSoldOut && widget.tierAccessible;
    final buttonLabel = match.isSoldOut
        ? 'SOLD OUT'
        : !widget.tierAccessible
        ? 'EARLY ACCESS ONLY'
        : !match.isOnSale
        ? 'SALES CLOSED'
        : 'BUY TICKET';
    final cardPadding = widget.isCompact ? space.x4 : space.x5;
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
        ? colors.danger.withValues(alpha: 0.18)
        : !widget.tierAccessible && match.isOnSale
        ? RsColors.rsGold.withValues(alpha: 0.16)
        : match.isOnSale
        ? colors.accent.withValues(alpha: 0.18)
        : RsColors.rsBlue.withValues(alpha: 0.14);
    final statusForeground = match.isSoldOut
        ? colors.danger
        : !widget.tierAccessible && match.isOnSale
        ? RsColors.rsGoldLight
        : RsColors.rsWhite;

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
              color: colors.teamSurface,
              gradient: RsColors.rsCardGradient,
              borderRadius: cardRadius,
              border: Border.all(color: RsColors.rsBlueBorder),
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
                          style: text.rayon(
                            theme.textTheme.labelSmall,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                            color: RsColors.rsGoldLight,
                          ),
                        ),
                      ),
                      SizedBox(width: space.x2),
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
                      SizedBox(width: widget.isCompact ? space.x2 : space.x3),
                      _VsBlock(
                        date: match.matchDate,
                        kickoffTime: match.kickoffTime,
                        isCompact: widget.isCompact,
                      ),
                      SizedBox(width: widget.isCompact ? space.x2 : space.x3),
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
                    spacing: space.x2,
                    runSpacing: space.x2,
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
                              const SizedBox(height: CoolSpace.x3),
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
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final radii = context.coolRadii;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final abbreviation = _teamAbbreviation(name);

    return Column(
      crossAxisAlignment: alignment,
      children: [
        Container(
          width: isCompact ? 40 : 46,
          height: isCompact ? 40 : 46,
          decoration: BoxDecoration(
            color: colors.overlaySurface.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(radii.sm),
            border: Border.all(color: colors.border),
          ),
          alignment: Alignment.center,
          child: Text(
            abbreviation,
            style: text.rayonCondensed(
              theme.textTheme.labelLarge,
              fontWeight: FontWeight.w800,
              color: RsColors.rsWhite,
            ),
          ),
        ),
        SizedBox(height: space.x2),
        Text(
          sideLabel,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: colors.tertiaryText,
          ),
        ),
        SizedBox(height: space.x1),
        Text(
          name,
          textAlign: alignment == CrossAxisAlignment.end
              ? TextAlign.right
              : TextAlign.left,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: text.rayonCondensed(
            isCompact
                ? theme.textTheme.titleLarge
                : theme.textTheme.headlineSmall,
            fontWeight: FontWeight.w800,
            color: RsColors.rsWhite,
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
    final space = context.coolSpace;
    final radii = context.coolRadii;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: space.x3, vertical: space.x2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(radii.pill),
        border: Border.all(color: foregroundColor.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final radii = context.coolRadii;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final dateLabel = DateFormat('d MMM').format(date).toUpperCase();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? space.x2 : space.x3,
        vertical: isCompact ? space.x2 : space.x2 + 2,
      ),
      decoration: BoxDecoration(
        color: colors.overlaySurface.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(radii.sm),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'VS',
            style: text.rayonCondensed(
              isCompact
                  ? theme.textTheme.titleSmall
                  : theme.textTheme.titleMedium,
              fontWeight: FontWeight.w800,
              color: colors.tertiaryText,
            ),
          ),
          SizedBox(height: space.x1),
          Text(
            '$dateLabel $kickoffTime',
            textAlign: TextAlign.center,
            style: text.mono(
              theme.textTheme.labelSmall,
              fontWeight: FontWeight.w700,
              color: RsColors.rsBluePale,
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
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    final space = context.coolSpace;
    final text = context.coolText;
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: space.x3, vertical: space.x2),
      decoration: BoxDecoration(
        color: highlight
            ? RsColors.rsGold.withValues(alpha: 0.16)
            : colors.overlaySurface.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(radii.sm),
        border: Border.all(
          color: highlight ? RsColors.rsGoldLight : colors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: highlight ? RsColors.rsGoldLight : RsColors.rsBluePale,
          ),
          SizedBox(width: space.x1 + 2),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: text.rayon(
                theme.textTheme.labelSmall,
                fontWeight: FontWeight.w700,
                color: highlight
                    ? RsColors.rsGoldLight
                    : RsColors.rsWhite.withValues(alpha: 0.84),
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
    final colors = context.coolSemanticColors;
    return Transform.translate(
      offset: const Offset(0, 0),
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: colors.appBackground,
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
      ..color = RsColors.rsBlueBorder.withValues(alpha: 0.8)
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
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          seatLabel.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            color: colors.secondaryText,
          ),
        ),
        SizedBox(height: space.x1 + 2),
        Text(
          _formatRwf(price),
          style: text.mono(
            theme.textTheme.titleLarge,
            fontWeight: FontWeight.w800,
            color: RsColors.rsGoldLight,
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
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radii.sm),
      child: Ink(
        padding: EdgeInsets.symmetric(horizontal: space.x3, vertical: space.x2),
        decoration: BoxDecoration(
          color: selected ? RsColors.rsBlue : colors.cardSurfaceStrong,
          borderRadius: BorderRadius.circular(radii.sm),
          border: Border.all(color: RsColors.rsBlueBorder),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: selected ? RsColors.rsWhite : colors.secondaryText,
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
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    final theme = Theme.of(context);
    return SizedBox(
      height: CoolTapTargets.comfortable,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: enabled ? RsColors.rsBlue : colors.cardSurfaceStrong,
          borderRadius: BorderRadius.circular(radii.sm),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(radii.sm),
            child: Center(
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: enabled ? RsColors.rsWhite : colors.tertiaryText,
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
        const SizedBox(height: CoolSpace.x3),
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
        const SizedBox(height: CoolSpace.x3),
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
