part of '../screens/tickets_screen.dart';


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
          const SizedBox(height: CoolSpace.x6),

          // Match summary
          RsMatchCard(match: match, isCompact: true, onBuyTap: () {}),
          const SizedBox(height: CoolSpace.x6),

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
          const SizedBox(height: CoolSpace.x3),
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
                                ? RsColors.rsRed
                                : colors.inputSurface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: selected
                                  ? RsColors.rsRedBorder
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
                              const SizedBox(height: CoolSpace.x1),
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
          const SizedBox(height: CoolSpace.x6),

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
          const SizedBox(height: CoolSpace.x3),
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
                              ? RsColors.rsRed
                              : colors.inputSurface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected
                                ? RsColors.rsRedBorder
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
          const SizedBox(height: CoolSpace.x7),

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
              const SizedBox(height: CoolSpace.x1),
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
          const SizedBox(height: CoolSpace.x7),

          CoolCard(
            borderColor: RsColors.rsRedBorder,
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
                const SizedBox(height: CoolSpace.x2),
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
                const SizedBox(height: CoolSpace.x2),
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
          const SizedBox(height: CoolSpace.x6),

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
