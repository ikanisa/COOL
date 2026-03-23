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
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_toast.dart';
import '../../../../shared/widgets/qr_share_sheet.dart';
import '../../../../shared/widgets/rs_match_card.dart';
import '../models/rs_models.dart';

import '../rayon_payment.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../widgets/rayon_screen_scaffold.dart';
import '../../widgets/rayon_state_views.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../shared/widgets/cool_bottom_sheet.dart';

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
    final paymentRoute = ref.watch(rayonPaymentRouteProvider).valueOrNull;

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
                    _TicketHubCommandCard(
                      hub: hub,
                      paymentRouteReady: paymentRoute != null,
                    ),
                    const SizedBox(height: CoolSpace.x4),
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
                        labelStyle: text.rayon(
                          Theme.of(context).textTheme.titleSmall,
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                        unselectedLabelStyle: text.rayon(
                          Theme.of(context).textTheme.bodyMedium,
                          color: colors.secondaryText,
                          fontWeight: FontWeight.w700,
                        ),
                        padding: const EdgeInsets.all(4),
                        tabs: const [
                          Tab(text: 'On Sale', height: 48),
                          Tab(text: 'Upcoming', height: 48),
                          Tab(text: 'My Tickets', height: 48),
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
                        onTap: () => context.push(
                          '/partners/rayon-sports/tickets/my-tickets',
                        ),
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
                color: colors.primaryText,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: CoolSpace.x2),
            Text(
              'Tickets and entry passes appear here as fixtures open for sale or allocation.',
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
