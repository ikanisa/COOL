import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/config/deep_link_config.dart';
import '../../../../core/providers/production_redesign_provider.dart';
import '../../../../core/providers/referral_providers.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/status/cool_status_awarder.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/theme/cool_palette.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../core/theme/rs_text_styles.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/cool_toast.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/qr_share_sheet.dart';
import '../../../../shared/widgets/rs_match_card.dart';
import '../models/rs_models.dart';

import '../rayon_payment.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../widgets/rayon_screen_scaffold.dart';
import '../../widgets/rayon_state_views.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../shared/widgets/cool_bottom_sheet.dart';

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
    final colors = context.coolSemanticColors;
    final ticketHub = ref.watch(rayonTicketHubProvider);
    final paymentRoute = ref.watch(rayonPaymentRouteProvider).valueOrNull;
    final useProductionRedesign = ref.watch(
      productionRedesignEnabledProvider(
        const ProductionRedesignScope(
          route: ProductionRedesignRoutes.rayonTickets,
          partner: 'rayon',
        ),
      ),
    );

    return ticketHub.when(
      data: (hub) {
        final onSale = hub.onSaleMatches;
        final upcoming = hub.upcomingMatches;
        return RayonScreenScaffold(
          title: context.l10n.tickets,
          fallbackLocation: AppRoutes.rayonHome,
          scrollable: false,
          actions: [
            IconButton(
              onPressed: onSale.isEmpty ? null : () => _shareTicketsHub(onSale),
              tooltip: context.l10n.shareTickets,
              icon: const Icon(
                Icons.ios_share_rounded,
                color: AppColors.rsWhite,
                size: 22,
              ),
            ),
            IconButton(
              onPressed: () => context.push(AppRoutes.rayonMyTickets),
              tooltip: context.l10n.myTickets1,
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
                    if (useProductionRedesign) ...[
                      _TicketHubCommandCard(
                        hub: hub,
                        paymentRouteReady: paymentRoute != null,
                      ),
                      const SizedBox(height: 16),
                    ],
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            colors.cardSurfaceStrong.withValues(alpha: 0.92),
                            colors.cardSurface.withValues(alpha: 0.82),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(CoolRadii.md),
                        border: Border.all(
                          color: colors.borderStrong,
                          width: 1.2,
                        ),
                        boxShadow: CoolShadows.clay(
                          Theme.of(context).brightness,
                          strength: 0.45,
                        ),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        onTap: (_) => setState(() {}),
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicator: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF15498F), Color(0xFF0B2A63)],
                          ),
                          borderRadius: BorderRadius.circular(CoolRadii.sm),
                        ),
                        dividerHeight: 0,
                        labelColor: Colors.white,
                        unselectedLabelColor: colors.secondaryText,
                        labelStyle: RsTextStyles.badge(
                          color: Colors.white,
                        ).copyWith(fontSize: 15, fontWeight: FontWeight.w800),
                        unselectedLabelStyle: RsTextStyles.badge(
                          color: colors.secondaryText,
                        ).copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                        padding: const EdgeInsets.all(4),
                        tabs: const [
                          Tab(text: 'On Sale', height: 48),
                          Tab(text: 'Upcoming', height: 48),
                          Tab(text: 'My Tickets', height: 48),
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return CoolCard(
      backgroundColor: colors.cardSurfaceStrong.withValues(alpha: 0.86),
      borderColor: colors.borderStrong,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CoolSpace.x3),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: colors.routeSurface,
                borderRadius: BorderRadius.circular(CoolRadii.lg),
                border: Border.all(color: colors.borderStrong),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.confirmation_number_outlined,
                size: 30,
                color: colors.primaryText,
              ),
            ),
            const SizedBox(height: CoolSpace.x5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: CoolSpace.x2),
            Text(
              'Ticket availability and personal entry passes will appear here as fixtures move through sale and allocation windows.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPurchaseSheet(BuildContext context, RsMatch match) {
    final palette = context.coolPalette;
    final paymentRoute = ref.read(rayonPaymentRouteProvider).valueOrNull;
    showCoolBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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

class _TicketHubCommandCard extends StatelessWidget {
  const _TicketHubCommandCard({
    required this.hub,
    required this.paymentRouteReady,
  });

  final RayonTicketHubData hub;
  final bool paymentRouteReady;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
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
            style: theme.textTheme.labelLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
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
                      style: GoogleFonts.barlow(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Verified pricing, tier-aware access, and disciplined digital entry for every fixture.',
                      style: GoogleFonts.barlow(
                        fontSize: 15,
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
                  style: GoogleFonts.dmMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: tier == FanTier.silver ? palette.bg : Colors.white,
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
                    style: GoogleFonts.barlow(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white.withValues(alpha: 0.82),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${featuredMatch.homeTeam} vs ${featuredMatch.awayTeam}',
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${DateFormat('d MMM').format(featuredMatch.matchDate)} · ${featuredMatch.kickoffTime} · ${featuredMatch.venue}',
                    style: GoogleFonts.barlow(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.8)),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.barlow(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
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
                        style: GoogleFonts.barlow(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
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
                        style: GoogleFonts.barlow(
                          fontSize: 11,
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
                  style: GoogleFonts.dmMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.secondaryText,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${ticket.seatType.name.toUpperCase()} · ${NumberFormat.decimalPattern('en').format(ticket.amountPaid)} RWF',
                  style: GoogleFonts.barlow(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.rsGoldLight,
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
    final palette = context.coolPalette;
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
              color: palette.border2,
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
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: palette.text3,
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
                    child: GestureDetector(
                      onTap: () => setState(() => _seat = type),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: selected ? RsColors.rsBlue : palette.surface2,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: selected
                                ? RsColors.rsBlueBorder
                                : palette.border,
                            width: 1.5,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Column(
                          children: [
                            Text(
                              type.label.toUpperCase(),
                              style: RsTextStyles.clubName(
                                color: selected ? Colors.white : palette.text,
                              ).copyWith(fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${type.priceFor(match)} RWF',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontFamily: GoogleFonts.dmMono().fontFamily,
                                    color: selected
                                        ? Colors.white70
                                        : palette.text3,
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
          const SizedBox(height: 24),

          // Quantity selector
          Text(
            'QUANTITY',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: palette.text3,
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
                  child: GestureDetector(
                    onTap: () => setState(() => _qty = q),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 60,
                      height: 52,
                      decoration: BoxDecoration(
                        color: selected ? RsColors.rsBlue : palette.surface2,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected
                              ? RsColors.rsBlueBorder
                              : palette.border,
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$q',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w900,
                              fontFamily: GoogleFonts.dmMono().fontFamily,
                              color: selected ? Colors.white : palette.text,
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
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: palette.text2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${NumberFormat.decimalPattern('en').format(_total)} RWF',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontFamily: GoogleFonts.dmMono().fontFamily,
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
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: AppColors.rsWhite,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.paymentRoute == null
                      ? 'No active backend route'
                      : widget.paymentRoute!.ussdCode(_total),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    fontFamily: GoogleFonts.dmMono().fontFamily,
                    color: RsColors.rsGoldLight,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.paymentRoute == null
                      ? 'An admin must activate a recipient code before ticket checkout can open.'
                      : 'Pay to ${widget.paymentRoute!.payToLabel}. Amount ${widget.paymentRoute!.amountLabel(_total)}. Fees ${widget.paymentRoute!.feesLabel()}. Ticket entry unlocks after SMS reconciliation for ${widget.paymentRoute!.reconciliationLabel}.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: AppColors.rsWhite.withValues(alpha: 0.7),
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
