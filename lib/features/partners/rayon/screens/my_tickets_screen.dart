import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/rs_digital_ticket.dart';
import '../models/rs_models.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../../../shared/widgets/core_app_scaffold.dart';
import '../../widgets/rayon_state_views.dart';
import '../../../../core/l10n/l10n.dart';

class MyTicketsScreen extends ConsumerWidget {
  const MyTicketsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final ticketsAsync = ref.watch(rayonUserTicketsProvider);
    final paymentRoute = ref.watch(rayonPaymentRouteProvider).valueOrNull;

    return CoreAppScaffold(
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
                    child: CoolCard(
                      backgroundColor: colors.cardSurfaceStrong,
                      borderColor: colors.borderStrong,
                      child: Column(
                        children: [
                          const SizedBox(height: CoolSpace.x4),
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              color: colors.teamSurface,
                              borderRadius: BorderRadius.circular(CoolRadii.lg),
                              border: Border.all(color: colors.borderStrong),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.confirmation_number_outlined,
                              size: 34,
                              color: colors.primaryText,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'No tickets yet',
                            style: text.rayonCondensed(
                              theme.textTheme.headlineMedium,
                              fontWeight: FontWeight.w900,
                              color: colors.primaryText,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Your confirmed match entries appear here after checkout completes.',
                            textAlign: TextAlign.center,
                            style: text.rayon(
                              theme.textTheme.bodyMedium,
                              fontWeight: FontWeight.w600,
                              color: colors.secondaryText,
                              height: 1.4,
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
                        style: text.rayon(
                          theme.textTheme.bodySmall,
                          fontWeight: FontWeight.w600,
                          color: colors.secondaryText,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: CoolSpace.x3),
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
                        color: colors.accent,
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
                        color: colors.tertiaryText,
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
    final textStyle = context.coolText;
    final theme = Theme.of(context);
    return Text(
      text,
      style: textStyle.rayon(
        theme.textTheme.labelSmall,
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
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final dateLabel = DateFormat(
      'd MMM',
    ).format(ticket.matchDate).toUpperCase();
    final isUsed = ticket.status == RsTicketStatus.used;

    return CoolCard(
      backgroundColor: colors.cardSurface,
      borderColor: colors.borderStrong,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.overlaySurface,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.qr_code_rounded,
              size: 18,
              color: isUsed ? colors.tertiaryText : RsColors.rsBlue,
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
                  style: text.rayon(
                    theme.textTheme.bodyMedium,
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$dateLabel · ${ticket.seatType}',
                  style: text.mono(
                    theme.textTheme.labelSmall,
                    fontWeight: FontWeight.w600,
                    color: colors.tertiaryText,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colors.overlaySurface,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isUsed ? 'USED' : 'CANCELLED',
              style: text.rayon(
                theme.textTheme.labelSmall,
                fontWeight: FontWeight.w700,
                color: colors.tertiaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
