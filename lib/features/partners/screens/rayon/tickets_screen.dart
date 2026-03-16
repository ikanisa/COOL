import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/config/deep_link_config.dart';
import '../../../../core/providers/referral_providers.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/status/cool_status_awarder.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/cool_toast.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/qr_share_sheet.dart';
import '../../../../shared/widgets/rs_match_card.dart';
import '../../rayon/models/rs_models.dart';

import '../../rayon/rayon_payment.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../widgets/rayon_screen_scaffold.dart';
import '../../widgets/rayon_state_views.dart';

class TicketsScreen extends ConsumerStatefulWidget {
  const TicketsScreen({
    this.referralParameters = const <String, String>{},
    super.key,
  });

  final Map<String, String> referralParameters;

  @override
  ConsumerState<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends ConsumerState<TicketsScreen>
    with SingleTickerProviderStateMixin, CoolStatusAwarder {
  late final TabController _tabController;

  final Map<String, SelectedSeatType> _selectedSeats = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  SelectedSeatType _seatForMatch(RsMatch match) {
    return _selectedSeats[match.id] ?? SelectedSeatType.general;
  }

  String? get _referralInviteId {
    final fromRoute = widget.referralParameters['ri']?.trim();
    if (fromRoute != null && fromRoute.isNotEmpty) {
      return fromRoute;
    }

    return ref.read(activeReferralAttributionProvider)?.inviteId;
  }

  void _setSeat(String matchId, SelectedSeatType seat) {
    setState(() => _selectedSeats[matchId] = seat);
  }

  @override
  Widget build(BuildContext context) {
    final ticketHub = ref.watch(rayonTicketHubProvider);
    final paymentRoute = ref.watch(rayonPaymentRouteProvider).valueOrNull;

    return ticketHub.when(
      data: (hub) {
        final isGoldPlus =
            hub.currentTier == FanTier.gold ||
            hub.currentTier == FanTier.platinum;

        final onSale = hub.onSaleMatches;
        final upcoming = hub.upcomingMatches;
        return RayonScreenScaffold(
          title: 'Tickets',
          fallbackLocation: AppRoutes.rayonHome,
          scrollable: false,
          actions: [
            IconButton(
              onPressed: onSale.isEmpty ? null : () => _shareTicketsHub(onSale),
              tooltip: 'Share tickets',
              icon: const Icon(
                Icons.ios_share_rounded,
                color: AppColors.rsWhite,
                size: 22,
              ),
            ),
            IconButton(
              onPressed: () => context.push(AppRoutes.rayonMyTickets),
              tooltip: 'My tickets',
              icon: const Icon(
                Icons.confirmation_number_outlined,
                color: AppColors.rsWhite,
                size: 22,
              ),
            ),
          ],
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        onTap: (_) => setState(() {}),
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicator: BoxDecoration(
                          color: RsColors.rsBlue,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        dividerHeight: 0,
                        labelColor: Colors.white,
                        unselectedLabelColor: AppColors.text3,
                        labelStyle: GoogleFonts.barlow(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        unselectedLabelStyle: GoogleFonts.barlow(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        padding: const EdgeInsets.all(3),
                        tabs: [
                          Tab(text: 'On Sale (${onSale.length})', height: 36),
                          Tab(
                            text: 'Upcoming (${upcoming.length})',
                            height: 36,
                          ),
                          const Tab(text: 'My Tickets', height: 36),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ]),
                ),
              ),
              ..._buildTabSlivers(context, hub, onSale, upcoming),
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        );
      },
      loading: RayonLoadingView.new,
      error: (error, _) => RayonErrorView(
        message: error.toString(),
        onRetry: () {
          ref.invalidate(rayonMatchesProvider);
          ref.invalidate(rayonUserMembershipProvider);
          ref.invalidate(rayonUserTicketsProvider);
        },
      ),
    );
  }

  Future<void> _shareTicketsHub(List<RsMatch> onSale) async {
    final featuredMatch = onSale.first;
    final baseUri = DeepLinkConfig.matchUri(featuredMatch.id);

    var shareUri = baseUri;
    try {
      final referralLink = await ref
          .read(referralRepositoryProvider)
          .createInviteLink(
            inviteCode: 'RAYON-TICKETS-${featuredMatch.id}',
            baseUri: baseUri,
            shareChannel: 'qr_sheet',
            campaignId: 'rayon_tickets',
          );
      shareUri = referralLink.uri;
    } catch (_) {
      // Fall back to the plain route if referral provisioning fails.
    }

    if (!mounted) {
      return;
    }

    await QrShareSheet.show(
      context,
      groupName: 'Rayon Tickets',
      inviteUrl: shareUri.toString(),
      sheetTitle: 'Share Ticket Hub',
      sheetSubtitle: 'Invite supporters to buy',
      shareText: 'Buy Rayon Sports tickets on Cool: ${shareUri.toString()}',
      analyticsTargetType: 'rayon_tickets',
    );
  }

  List<Widget> _buildTabSlivers(
    BuildContext context,
    RayonTicketHubData hub,
    List<RsMatch> onSale,
    List<RsMatch> upcoming,
  ) {
    switch (_tabController.index) {
      case 0:
        if (onSale.isEmpty) {
          return <Widget>[
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              sliver: SliverToBoxAdapter(
                child: _emptyState('No matches on sale right now.'),
              ),
            ),
          ];
        }
        return <Widget>[
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final match = onSale[index];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == onSale.length - 1 ? 0 : 12,
                  ),
                  child: RsMatchCard(
                    match: match,
                    selectedSeat: _seatForMatch(match),
                    onSelectedSeatChanged: (seat) => _setSeat(match.id, seat),
                    tierAccessible: match.isAccessibleForTier(hub.currentTier),
                    onBuyTap: () => _showPurchaseSheet(context, match),
                  ),
                );
              }, childCount: onSale.length),
            ),
          ),
        ];
      case 1:
        if (upcoming.isEmpty) {
          return <Widget>[
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              sliver: SliverToBoxAdapter(
                child: _emptyState('No upcoming matches scheduled.'),
              ),
            ),
          ];
        }
        return <Widget>[
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final match = upcoming[index];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == upcoming.length - 1 ? 0 : 12,
                  ),
                  child: RsMatchCard(
                    match: match,
                    isCompact: true,
                    onBuyTap: () {},
                  ),
                );
              }, childCount: upcoming.length),
            ),
          ),
        ];
      case 2:
        if (hub.tickets.isEmpty) {
          return <Widget>[
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              sliver: SliverToBoxAdapter(
                child: _emptyState(
                  'No tickets yet. Buy a match ticket to see it here.',
                ),
              ),
            ),
          ];
        }
        return <Widget>[
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final ticket = hub.tickets[index];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == hub.tickets.length - 1 ? 0 : 14,
                  ),
                  child: Semantics(
                    button: true,
                    label: 'View ticket for ${ticket.matchTitle}',
                    child: GestureDetector(
                      onTap: () => context.push(
                        '/partners/rayon-sports/tickets/my-tickets',
                      ),
                      child: _CompactTicketRow(ticket: ticket),
                    ),
                  ),
                );
              }, childCount: hub.tickets.length),
            ),
          ),
        ];
      default:
        return const <Widget>[];
    }
  }

  Widget _emptyState(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: GoogleFonts.barlow(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.text3,
          ),
        ),
      ),
    );
  }

  void _showPurchaseSheet(BuildContext context, RsMatch match) {
    final paymentRoute = ref.read(rayonPaymentRouteProvider).valueOrNull;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => _TicketPurchaseSheet(
        match: match,
        paymentRoute: paymentRoute,
        onPay: (seatType, qty) async {
          final notifier = ref.read(rayonSportsProvider.notifier);
          Navigator.of(sheetCtx).pop();
          try {
            final referralInviteId = _referralInviteId;
            final message = await notifier.buyTicket(
              match: match,
              seatType: seatType.label,
              quantity: qty,
              referralInviteId: referralInviteId,
            );
            if (referralInviteId != null && referralInviteId.isNotEmpty) {
              ref
                  .read(activeReferralAttributionProvider.notifier)
                  .clearIfMatches(referralInviteId);
            }
            ref.invalidate(rayonUserTicketsProvider);
            if (!context.mounted) return;
            // Points are awarded server-side after payment confirmation.
            CoolToast.info(context, message);
          } catch (error) {
            if (!context.mounted) return;
            CoolToast.error(context, error.toString());
          }
        },
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
    final dateLabel = DateFormat(
      'd MMM',
    ).format(ticket.matchDate).toUpperCase();
    final isValid = ticket.status == RsTicketStatus.valid;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: RsColors.rsCardGradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isValid
              ? AppColors.accent.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          // Mini QR placeholder
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.rsWhite,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.qr_code_rounded,
              size: 22,
              color: RsColors.rsBlue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ticket.matchTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.barlow(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.rsWhite,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$dateLabel · ${ticket.seatType}',
                  style: GoogleFonts.dmMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text3,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isValid
                  ? AppColors.accent.withValues(alpha: 0.15)
                  : AppColors.surface3,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              ticket.status.label.toUpperCase(),
              style: GoogleFonts.barlow(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isValid ? AppColors.accent : AppColors.text3,
              ),
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
    final match = widget.match;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 18),

          // Match summary
          RsMatchCard(match: match, isCompact: true, onBuyTap: () {}),
          const SizedBox(height: 18),

          // Seat type selector
          Text(
            'SEAT TYPE',
            style: GoogleFonts.barlow(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.text2,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: SelectedSeatType.values.map((type) {
              final selected = type == _seat;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: type == SelectedSeatType.general ? 6 : 0,
                    left: type == SelectedSeatType.vip ? 6 : 0,
                  ),
                  child: Semantics(
                    selected: selected,
                    label: '${type.label} seat type',
                    child: GestureDetector(
                      onTap: () => setState(() => _seat = type),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: selected
                              ? RsColors.rsBlue
                              : AppColors.surface2,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? RsColors.rsBlueBorder
                                : AppColors.border,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Column(
                          children: [
                            Text(
                              type.label,
                              style: GoogleFonts.barlowCondensed(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: selected
                                    ? Colors.white
                                    : AppColors.text2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${type.priceFor(match)} RWF',
                              style: GoogleFonts.dmMono(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? Colors.white70
                                    : AppColors.text3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Quantity selector
          Text(
            'QUANTITY',
            style: GoogleFonts.barlow(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.text2,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [1, 2, 3].map((q) {
              final selected = q == _qty;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Semantics(
                  selected: selected,
                  label: 'Quantity $q',
                  child: GestureDetector(
                    onTap: () => setState(() => _qty = q),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 52,
                      height: 44,
                      decoration: BoxDecoration(
                        color: selected ? RsColors.rsBlue : AppColors.surface2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? RsColors.rsBlueBorder
                              : AppColors.border,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$q',
                        style: GoogleFonts.dmMono(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: selected ? Colors.white : AppColors.text2,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),

          // Total
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Total:',
                style: GoogleFonts.barlow(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text2,
                ),
              ),
              Text(
                '${NumberFormat.decimalPattern('en').format(_total)} RWF',
                style: GoogleFonts.dmMono(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: RsColors.rsGoldLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          CoolCard(
            borderColor: RsColors.rsBlueBorder,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.paymentRoute == null
                      ? 'Rayon Sports payment routing pending'
                      : '${widget.paymentRoute!.partnerName} checkout',
                  style: GoogleFonts.barlow(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.rsWhite,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.paymentRoute == null
                      ? 'No active backend route'
                      : widget.paymentRoute!.ussdCode(_total),
                  style: GoogleFonts.dmMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: RsColors.rsGoldLight,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.paymentRoute == null
                      ? 'An admin must activate a recipient code before ticket checkout can open.'
                      : 'Pay to ${widget.paymentRoute!.payToLabel}. Amount ${widget.paymentRoute!.amountLabel(_total)}. Fees ${widget.paymentRoute!.feesLabel()}. Ticket entry unlocks after SMS reconciliation for ${widget.paymentRoute!.reconciliationLabel}.',
                  style: GoogleFonts.barlow(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text2,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Pay button
          CoolButton(
            label: widget.paymentRoute == null
                ? 'Payment route unavailable'
                : 'Pay via ${widget.paymentRoute!.providerLabel}',
            onTap: widget.paymentRoute == null
                ? () {}
                : () => widget.onPay(_seat, _qty),
            icon: Icons.phone_in_talk_outlined,
          ),
        ],
      ),
    );
  }
}
