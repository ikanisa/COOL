import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/config/deep_link_config.dart';
import '../../../../core/providers/referral_providers.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/status/cool_status_awarder.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../core/theme/rs_text_styles.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_toast.dart';
import '../../../../shared/widgets/qr_share_sheet.dart';
import '../../../../shared/widgets/rs_match_card.dart';
import '../../../../shared/widgets/rs_seat_map.dart';
import '../models/rs_models.dart';

import '../rayon_payment.dart';
import '../providers/rayon_sports_provider.dart';
import '../../../../shared/widgets/core_app_scaffold.dart';
import '../widgets/rayon_state_views.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../shared/widgets/cool_bottom_sheet.dart';
import '../../../../shared/widgets/cool_empty_view.dart';

part '../widgets/tickets_screen_parts.dart';

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
    final text = context.coolText;
    final ticketHub = ref.watch(rayonTicketHubProvider);

    return ticketHub.when(
      data: (hub) {
        final onSale = hub.onSaleMatches;
        final upcoming = hub.upcomingMatches;
        return CoreAppScaffold(
          title: context.l10n.tickets,
          fallbackLocation: AppRoutes.rayonHome,
          scrollable: false,
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 8, top: 10, bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: hub.currentTier.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: hub.currentTier.color.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                hub.currentTier.label.toUpperCase(),
                style: text.mono(
                  Theme.of(context).textTheme.labelSmall,
                  fontWeight: FontWeight.w800,
                  color: hub.currentTier == FanTier.bronze
                      ? colors.appBackground
                      : Colors.white,
                ),
              ),
            ),
            IconButton(
              onPressed: onSale.isEmpty ? null : () => _shareTicketsHub(onSale),
              tooltip: context.l10n.shareTickets,
              icon: Icon(
                Icons.ios_share_rounded,
                color: colors.primaryText,
                size: 22,
              ),
            ),
            IconButton(
              onPressed: () => context.push(AppRoutes.rayonMyTickets),
              tooltip: context.l10n.myTickets1,
              icon: Icon(
                Icons.confirmation_number_outlined,
                color: colors.primaryText,
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
                    CoolCard(
                      variant: CoolCardVariant.glass,
                      cardPadding: CoolCardPadding.none,
                      padding: const EdgeInsets.all(4),
                      borderRadius: CoolRadii.md,
                      child: TabBar(
                        controller: _tabController,
                        onTap: (_) => setState(() {}),
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicator: BoxDecoration(
                          color: RsColors.rsRed,
                          borderRadius: BorderRadius.circular(CoolRadii.md - 1),
                          boxShadow: const [
                            BoxShadow(
                              color: RsColors.rsRedGlow,
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        dividerHeight: 0,
                        labelColor: Colors.white,
                        unselectedLabelColor: colors.secondaryText,
                        labelStyle: RsTextStyles.badge(
                          color: Colors.white,
                        ).copyWith(fontSize: 13),
                        unselectedLabelStyle: RsTextStyles.badge(
                          color: colors.secondaryText,
                        ).copyWith(fontSize: 13),
                        tabs: const [
                          Tab(text: 'ON SALE', height: 40),
                          Tab(text: 'UPCOMING', height: 40),
                          Tab(text: 'MY TICKETS', height: 40),
                        ],
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x4),
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
          // ── Seat map zone picker ──
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            sliver: SliverToBoxAdapter(
              child: RsSeatMap(
                selected: _seatForMatch(onSale.first),
                onZoneSelected: (zone) {
                  for (final match in onSale) {
                    _setSeat(match.id, zone);
                  }
                },
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
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
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(CoolRadii.md),
                        onTap: () => context.push(AppRoutes.rayonMyTickets),
                        child: _CompactTicketRow(ticket: ticket),
                      ),
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
      padding: const EdgeInsets.only(top: CoolSpace.x5),
      child: CoolEmptyView(
        message: message,
        icon: Icons.confirmation_number_outlined,
      ),
    );
  }

  void _showPurchaseSheet(BuildContext context, RsMatch match) {
    final colors = context.coolSemanticColors;
    final paymentRoute = ref.read(rayonPaymentRouteProvider).valueOrNull;
    showCoolBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.elevatedBackground,
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
