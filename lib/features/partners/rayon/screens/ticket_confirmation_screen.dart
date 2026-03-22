import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/config/deep_link_config.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/providers/production_redesign_provider.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/theme/cool_palette.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/rs_digital_ticket.dart';
import '../../../../shared/widgets/share_card.dart';
import '../models/rs_models.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../widgets/rayon_screen_scaffold.dart';
import '../../widgets/rayon_state_views.dart';

class TicketConfirmationScreen extends ConsumerWidget {
  const TicketConfirmationScreen({required this.ticketId, super.key});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.coolPalette;
    final colors = context.coolSemanticColors;
    final l10n = context.l10n;
    final useProductionRedesign = ref.watch(
      productionRedesignEnabledProvider(
        const ProductionRedesignScope(
          route: ProductionRedesignRoutes.rayonTicketConfirmation,
          partner: 'rayon',
        ),
      ),
    );
    final ticketAsync = ref.watch(rayonUserTicketByIdProvider(ticketId));
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return RayonScreenScaffold(
      title: l10n.ticketConfirmationScreenTitle,
      fallbackLocation: AppRoutes.rayonTickets,
      scrollable: false,
      child: ticketAsync.when(
        data: (ticket) {
          if (ticket == null) {
            return RayonErrorView(
              message: l10n.ticketConfirmationNotFound,
              onRetry: () => ref.invalidate(rayonUserTicketsProvider),
            );
          }

          final statusMeta = _statusMeta(ticket.status, l10n);
          final statusIcon = Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.accent.withValues(alpha: 0.15),
              border: Border.all(
                color: statusMeta.color.withValues(alpha: 0.4),
                width: 2,
              ),
            ),
            alignment: Alignment.center,
            child: Icon(statusMeta.icon, size: 40, color: statusMeta.color),
          );

          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: Column(
                      children: [
                        if (useProductionRedesign) ...[
                          _TicketConfirmationCommandCard(
                            ticket: ticket,
                            statusMeta: statusMeta,
                          ),
                          const SizedBox(height: 18),
                        ] else
                          const SizedBox(height: 30),
                        if (disableAnimations)
                          statusIcon
                        else
                          statusIcon
                              .animate()
                              .scaleXY(
                                begin: 0,
                                end: 1,
                                duration: 500.ms,
                                curve: Curves.elasticOut,
                              )
                              .fadeIn(duration: 300.ms),
                        const SizedBox(height: 24),
                        Text(
                          statusMeta.title,
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            color: AppColors.rsWhite,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          statusMeta.subtitle,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.barlow(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: colors.secondaryText,
                          ),
                        ),
                        const SizedBox(height: 24),
                        RsDigitalTicket(ticket: ticket),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: CoolButton(
                                label: l10n.ticketBackToTickets,
                                variant: CoolButtonVariant.secondary,
                                onTap: () => context.go(AppRoutes.rayonTickets),
                                icon: Icons.confirmation_number_outlined,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          statusMeta.note,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.barlow(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.secondaryText,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 20),
                        ShareCard(
                          title: l10n.ticketShareMatchTitle,
                          icon: Icons.sports_soccer_rounded,
                          subtitle: ticket.matchTitle,
                          shareUrl: DeepLinkConfig.matchUri(
                            ticket.matchId,
                          ).toString(),
                          shareText: l10n.ticketShareMatchText(
                            ticket.matchTitle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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

class _TicketConfirmationCommandCard extends StatelessWidget {
  const _TicketConfirmationCommandCard({
    required this.ticket,
    required this.statusMeta,
  });

  final RsTicket ticket;
  final _TicketStatusMeta statusMeta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CoolCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF06152D), Color(0xFF0B2351), Color(0xFF143B72)],
      ),
      borderColor: AppColors.rsBlueBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Verified ticket record',
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
                      'Official Matchday Entry',
                      style: GoogleFonts.barlow(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Ticket identity, payment reference, and digital entry status are now recorded for matchday operations.',
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
              _TicketInfoPill(
                icon: statusMeta.icon,
                label: ticket.status.label,
                highlighted: true,
                color: statusMeta.color,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TicketInfoPill(
                icon: Icons.event_note_rounded,
                label: '${ticket.matchTitle} · ${ticket.kickoffTime}',
              ),
              _TicketInfoPill(icon: Icons.place_outlined, label: ticket.venue),
              _TicketInfoPill(
                icon: Icons.sell_outlined,
                label:
                    '${ticket.seatType.name.toUpperCase()} · ${ticket.amountPaid} RWF',
              ),
              _TicketInfoPill(
                icon: Icons.receipt_long_outlined,
                label: ticket.momoReference,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TicketInfoPill extends StatelessWidget {
  const _TicketInfoPill({
    required this.icon,
    required this.label,
    this.highlighted = false,
    this.color,
  });

  final IconData icon;
  final String label;
  final bool highlighted;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: highlighted
            ? (color ?? AppColors.accent).withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: highlighted
              ? (color ?? AppColors.accent).withValues(alpha: 0.28)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: highlighted
                ? (color ?? AppColors.accent)
                : Colors.white.withValues(alpha: 0.76),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.barlow(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: highlighted ? (color ?? AppColors.accent) : Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketStatusMeta {
  const _TicketStatusMeta({
    required this.title,
    required this.subtitle,
    required this.note,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final String note;
  final IconData icon;
  final Color color;
}

_TicketStatusMeta _statusMeta(RsTicketStatus status, AppLocalizations l10n) {
  return switch (status) {
    RsTicketStatus.pending => _TicketStatusMeta(
      title: l10n.ticketStatusPendingTitle,
      subtitle: l10n.ticketStatusPendingSubtitle,
      note: l10n.ticketStatusPendingNote,
      icon: Icons.hourglass_top_rounded,
      color: AppColors.rsGold,
    ),
    RsTicketStatus.valid => _TicketStatusMeta(
      title: l10n.ticketStatusValidTitle,
      subtitle: l10n.ticketStatusValidSubtitle,
      note: l10n.ticketStatusValidNote,
      icon: Icons.check_rounded,
      color: AppColors.accent,
    ),
    RsTicketStatus.used => _TicketStatusMeta(
      title: l10n.ticketStatusUsedTitle,
      subtitle: l10n.ticketStatusUsedSubtitle,
      note: l10n.ticketStatusUsedNote,
      icon: Icons.check_circle_outline_rounded,
      color: AppColors.text3,
    ),
    RsTicketStatus.cancelled ||
    RsTicketStatus.voided ||
    RsTicketStatus.refunded => _TicketStatusMeta(
      title: l10n.ticketStatusCancelledTitle,
      subtitle: l10n.ticketStatusCancelledSubtitle,
      note: l10n.ticketStatusCancelledNote,
      icon: Icons.block_rounded,
      color: AppColors.red,
    ),
  };
}
