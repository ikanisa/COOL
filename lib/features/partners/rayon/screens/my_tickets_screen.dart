import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/cool_palette.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/rs_digital_ticket.dart';
import '../models/rs_models.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../widgets/rayon_screen_scaffold.dart';
import '../../widgets/rayon_state_views.dart';
import '../../../../core/l10n/l10n.dart';

class MyTicketsScreen extends ConsumerWidget {
  const MyTicketsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.coolPalette;
    final ticketsAsync = ref.watch(rayonUserTicketsProvider);
    final paymentRoute = ref.watch(rayonPaymentRouteProvider).valueOrNull;

    return RayonScreenScaffold(
      title: context.l10n.myTickets,
      fallbackLocation: AppRoutes.rayonTickets,
      scrollable: false,
      child: ticketsAsync.when(
        data: (tickets) {
          if (tickets.isEmpty) {
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      children: [
                        const SizedBox(height: 40),
                        Text(
                          'No tickets yet',
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            color: AppColors.rsWhite,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Your confirmed match entries',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.barlow(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: palette.text2,
                          ),
                        ),
                        const SizedBox(height: 18),
                        CoolButton(
                          label: context.l10n.browseMatches,
                          onTap: () => context.go(AppRoutes.rayonTickets),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          final pending = tickets
              .where((t) => t.status == RsTicketStatus.pending)
              .toList();
          final ready = tickets
              .where((t) => t.status == RsTicketStatus.valid)
              .toList();
          final past = tickets
              .where(
                (t) =>
                    t.status == RsTicketStatus.used ||
                    t.status == RsTicketStatus.cancelled,
              )
              .toList();

          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (pending.isNotEmpty) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _SectionLabel(
                        text: context.l10n.paymentPending,
                        color: RsColors.rsGoldLight,
                      ),
                      const SizedBox(height: 10),
                      Text(
                         paymentRoute == null
                            ? 'Awaiting payment. QR unlocks after confirmation.'
                            : 'Awaiting ${paymentRoute.payToLabel} confirmation.',
                        style: GoogleFonts.barlow(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: palette.text2,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ]),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final ticket = pending[index];
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: index == pending.length - 1 ? 0 : 14,
                        ),
                        child: RsDigitalTicket(ticket: ticket),
                      );
                    }, childCount: pending.length),
                  ),
                ),
              ],
              if (ready.isNotEmpty) ...[
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    18,
                    pending.isNotEmpty ? 18 : 18,
                    18,
                    0,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _SectionLabel(
                        text: context.l10n.readyForEntry,
                        color: palette.accent,
                      ),
                      const SizedBox(height: 10),
                    ]),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final ticket = ready[index];
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: index == ready.length - 1 ? 0 : 14,
                        ),
                        child: RsDigitalTicket(ticket: ticket),
                      );
                    }, childCount: ready.length),
                  ),
                ),
              ],
              if (past.isNotEmpty) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 26, 18, 0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _SectionLabel(
                        text: context.l10n.pastTickets,
                        color: palette.text3,
                      ),
                      const SizedBox(height: 10),
                    ]),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final ticket = past[index];
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: index == past.length - 1 ? 0 : 10,
                        ),
                        child: _PastTicketRow(ticket: ticket),
                      );
                    }, childCount: past.length),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          );
        },
        loading: RayonLoadingView.new,
        error: (error, _) => RayonErrorView(
          message: error.toString(),
          onRetry: () => ref.invalidate(rayonUserTicketsProvider),
        ),
      ),
    );
  }
}

// ── Section label ────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.barlow(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: color,
        letterSpacing: 1,
      ),
    );
  }
}

// ── Past ticket compact row ──────────────────────────────────────────

class _PastTicketRow extends StatelessWidget {
  const _PastTicketRow({required this.ticket});

  final RsTicket ticket;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final dateLabel = DateFormat(
      'd MMM',
    ).format(ticket.matchDate).toUpperCase();
    final isUsed = ticket.status == RsTicketStatus.used;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          // Mini QR thumbnail
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: palette.surface3,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.qr_code_rounded,
              size: 18,
              color: isUsed ? palette.text3 : RsColors.rsBlue,
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
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: palette.text2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$dateLabel · ${ticket.seatType}',
                  style: GoogleFonts.dmMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: palette.text3,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: palette.surface3,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isUsed ? 'USED' : 'CANCELLED',
              style: GoogleFonts.barlow(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: palette.text3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}