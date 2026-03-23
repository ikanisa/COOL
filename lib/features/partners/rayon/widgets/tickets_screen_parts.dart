part of '../screens/tickets_screen.dart';

class _TicketHubCommandCard extends StatelessWidget {
  const _TicketHubCommandCard({
    required this.hub,
    required this.paymentRouteReady,
  });

  final RayonTicketHubData hub;
  final bool paymentRouteReady;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final tier = hub.currentTier;
    final featuredMatch = hub.onSaleMatches.isNotEmpty
        ? hub.onSaleMatches.first
        : (hub.upcomingMatches.isNotEmpty ? hub.upcomingMatches.first : null);

    return CoolCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF06162E), Color(0xFF0B2350), Color(0xFF14386E)],
      ),
      borderColor: RsColors.rsBlueBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Verified ticketing',
            style: text.rayon(
              theme.textTheme.labelLarge,
              color: Colors.white.withValues(alpha: 0.72),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.35,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Official Ticket Office',
                      style: text.rayonCondensed(
                        theme.textTheme.headlineMedium,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Verified pricing, tier-aware access, and disciplined digital entry for every fixture.',
                      style: text.rayon(
                        theme.textTheme.bodyMedium,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.8),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: tier.color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: tier.color.withValues(alpha: 0.36)),
                ),
                child: Text(
                  tier.label.toUpperCase(),
                  style: text.mono(
                    theme.textTheme.labelLarge,
                    fontWeight: FontWeight.w800,
                    color: tier == FanTier.silver
                        ? colors.appBackground
                        : Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TicketSignalPill(
                icon: Icons.confirmation_number_outlined,
                label: '${hub.onSaleMatches.length} on sale',
              ),
              _TicketSignalPill(
                icon: Icons.schedule_rounded,
                label: '${hub.upcomingMatches.length} upcoming',
              ),
              _TicketSignalPill(
                icon: Icons.verified_user_outlined,
                label: '${hub.tickets.length} in my tickets',
              ),
              _TicketSignalPill(
                icon: paymentRouteReady
                    ? Icons.shield_outlined
                    : Icons.timelapse_rounded,
                label: paymentRouteReady
                    ? 'Payment route live'
                    : 'Payment route syncing',
              ),
            ],
          ),
          if (featuredMatch != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(CoolRadii.md),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    featuredMatch.isOnSale
                        ? 'Priority fixture'
                        : 'Next fixture',
                    style: text.rayon(
                      theme.textTheme.labelLarge,
                      fontWeight: FontWeight.w800,
                      color: Colors.white.withValues(alpha: 0.82),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${featuredMatch.homeTeam} vs ${featuredMatch.awayTeam}',
                    style: text.rayonCondensed(
                      theme.textTheme.headlineLarge,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${DateFormat('d MMM').format(featuredMatch.matchDate)} · ${featuredMatch.kickoffTime} · ${featuredMatch.venue}',
                    style: text.mono(
                      theme.textTheme.bodySmall,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.76),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _TicketSignalPill(
                        icon: Icons.sell_outlined,
                        label:
                            '${NumberFormat.decimalPattern('en').format(featuredMatch.ticketGeneralPrice)} RWF general',
                      ),
                      _TicketSignalPill(
                        icon: Icons.workspace_premium_outlined,
                        label:
                            '${NumberFormat.decimalPattern('en').format(featuredMatch.ticketVipPrice)} RWF VIP',
                      ),
                      _TicketSignalPill(
                        icon: Icons.local_fire_department_outlined,
                        label: _ticketDemandSignal(featuredMatch),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TicketSignalPill extends StatelessWidget {
  const _TicketSignalPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = context.coolText;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.8)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.rayon(
                  theme.textTheme.labelLarge,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Compact ticket row (for My Tickets tab) ──────────────────────────

class _CompactTicketRow extends StatelessWidget {
  const _CompactTicketRow({required this.ticket});

  final RsTicket ticket;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final dateLabel = DateFormat(
      'd MMM',
    ).format(ticket.matchDate).toUpperCase();
    final isValid = ticket.status == RsTicketStatus.valid;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.cardSurfaceStrong.withValues(alpha: 0.92),
            colors.cardSurface.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(CoolRadii.md),
        border: Border.all(
          color: isValid
              ? colors.accent.withValues(alpha: 0.4)
              : colors.borderStrong,
        ),
        boxShadow: CoolShadows.clay(
          Theme.of(context).brightness,
          strength: 0.45,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.routeSurface,
              borderRadius: BorderRadius.circular(CoolRadii.sm),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.qr_code_rounded,
              size: 22,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        ticket.matchTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.rayonCondensed(
                          Theme.of(context).textTheme.titleLarge,
                          fontWeight: FontWeight.w800,
                          color: colors.primaryText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isValid
                            ? colors.accent.withValues(alpha: 0.16)
                            : colors.cardSurfaceStrong.withValues(alpha: 0.86),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        ticket.status.label.toUpperCase(),
                        style: text.rayon(
                          Theme.of(context).textTheme.labelLarge,
                          fontWeight: FontWeight.w800,
                          color: isValid ? colors.accent : colors.secondaryText,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '$dateLabel · ${ticket.match.kickoffTime} · ${ticket.match.venue}',
                  style: text.mono(
                    Theme.of(context).textTheme.bodyMedium,
                    fontWeight: FontWeight.w700,
                    color: colors.secondaryText,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${ticket.seatType.name.toUpperCase()} · ${NumberFormat.decimalPattern('en').format(ticket.amountPaid)} RWF',
                  style: text.rayon(
                    Theme.of(context).textTheme.bodyLarge,
                    fontWeight: FontWeight.w800,
                    color: RsColors.rsGoldLight,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _ticketDemandSignal(RsMatch match) {
  if (match.isSoldOut) {
    return 'Sold out';
  }
  if (match.capacity <= 0) {
    return match.isOnSale ? 'Official sale active' : 'Allocation pending';
  }

  final remainingRatio = match.remainingCapacity / match.capacity;
  if (remainingRatio <= 0.15) {
    return 'Final allocation';
  }
  if (remainingRatio <= 0.4) {
    return '${match.remainingCapacity} left';
  }
  return match.isOnSale ? 'Seats available' : 'Presale';
}

// ── Ticket Purchase Sheet ────────────────────────────────────────────

class _TicketPurchaseSheet extends StatefulWidget {
  const _TicketPurchaseSheet({
    required this.match,
    required this.onPay,
    this.paymentRoute,
  });

  final RsMatch match;
  final void Function(SelectedSeatType seatType, int qty) onPay;
  final PartnerPaymentRoute? paymentRoute;

  @override
  State<_TicketPurchaseSheet> createState() => _TicketPurchaseSheetState();
}

class _TicketPurchaseSheetState extends State<_TicketPurchaseSheet> {
  SelectedSeatType _seat = SelectedSeatType.general;
  int _qty = 1;

  int get _unitPrice => _seat.priceFor(widget.match);
  int get _total => _unitPrice * _qty;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final match = widget.match;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        22,
        16,
        22,
        MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: colors.borderStrong,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 24),

          // Match summary
          RsMatchCard(match: match, isCompact: true, onBuyTap: () {}),
          const SizedBox(height: 24),

          // Seat type selector
          Text(
            'SEAT TYPE',
            style: text.rayon(
              theme.textTheme.labelSmall,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: colors.tertiaryText,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: SelectedSeatType.values.map((type) {
              final selected = type == _seat;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: type == SelectedSeatType.general ? 8 : 0,
                    left: type == SelectedSeatType.vip ? 8 : 0,
                  ),
                  child: Semantics(
                    selected: selected,
                    label: '${type.label} seat type',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => setState(() => _seat = type),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: selected
                                ? RsColors.rsBlue
                                : colors.inputSurface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: selected
                                  ? RsColors.rsBlueBorder
                                  : colors.border,
                              width: 1.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Column(
                            children: [
                              Text(
                                type.label.toUpperCase(),
                                style: text.rayonCondensed(
                                  theme.textTheme.titleMedium,
                                  fontWeight: FontWeight.w800,
                                  color: selected
                                      ? Colors.white
                                      : colors.primaryText,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${type.priceFor(match)} RWF',
                                style: text.mono(
                                  theme.textTheme.bodySmall,
                                  fontWeight: FontWeight.w700,
                                  color: selected
                                      ? Colors.white70
                                      : colors.tertiaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // Quantity selector
          Text(
            'QUANTITY',
            style: text.rayon(
              theme.textTheme.labelSmall,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: colors.tertiaryText,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [1, 2, 3].map((q) {
              final selected = q == _qty;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Semantics(
                  selected: selected,
                  label: 'Quantity $q',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => setState(() => _qty = q),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 60,
                        height: 52,
                        decoration: BoxDecoration(
                          color: selected
                              ? RsColors.rsBlue
                              : colors.inputSurface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected
                                ? RsColors.rsBlueBorder
                                : colors.border,
                            width: 1.5,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$q',
                          style: text.mono(
                            theme.textTheme.headlineSmall,
                            fontWeight: FontWeight.w900,
                            color: selected ? Colors.white : colors.primaryText,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 32),

          // Total
          Column(
            children: [
              Text(
                'Total Amount',
                style: text.rayon(
                  theme.textTheme.labelLarge,
                  fontWeight: FontWeight.w700,
                  color: colors.secondaryText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${NumberFormat.decimalPattern('en').format(_total)} RWF',
                style: text.mono(
                  theme.textTheme.displaySmall,
                  fontWeight: FontWeight.w900,
                  color: RsColors.rsGoldLight,
                  letterSpacing: -1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          CoolCard(
            borderColor: RsColors.rsBlueBorder,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.paymentRoute == null
                      ? 'RAYON SPORTS PAYMENT ROUTING PENDING'
                      : '${widget.paymentRoute!.partnerName.toUpperCase()} CHECKOUT',
                  style: text.rayon(
                    theme.textTheme.labelSmall,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: colors.primaryText,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.paymentRoute == null
                      ? 'No active backend route'
                      : widget.paymentRoute!.ussdCode(_total),
                  style: text.mono(
                    theme.textTheme.headlineSmall,
                    fontWeight: FontWeight.w900,
                    color: RsColors.rsGoldLight,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.paymentRoute == null
                      ? 'An admin must activate a recipient code before ticket checkout can open.'
                      : 'Pay to ${widget.paymentRoute!.payToLabel}. Amount ${widget.paymentRoute!.amountLabel(_total)}. Fees ${widget.paymentRoute!.feesLabel()}. Ticket entry unlocks after SMS reconciliation for ${widget.paymentRoute!.reconciliationLabel}.',
                  style: text.rayon(
                    theme.textTheme.bodySmall,
                    fontWeight: FontWeight.w700,
                    color: colors.secondaryText,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Pay button
          CoolButton(
            label: widget.paymentRoute == null
                ? 'Payment route unavailable'
                : 'Pay via ${widget.paymentRoute!.providerLabel}',
            isDisabled: widget.paymentRoute == null,
            onTap: widget.paymentRoute == null
                ? null
                : () => widget.onPay(_seat, _qty),
            icon: Icons.phone_in_talk_outlined,
          ),
        ],
      ),
    );
  }
}
