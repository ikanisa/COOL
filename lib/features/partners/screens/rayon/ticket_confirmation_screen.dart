import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/config/deep_link_config.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/rs_digital_ticket.dart';
import '../../../../shared/widgets/share_card.dart';
import '../../rayon/models/rs_models.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../widgets/rayon_screen_scaffold.dart';
import '../../widgets/rayon_state_views.dart';

class TicketConfirmationScreen extends ConsumerWidget {
  const TicketConfirmationScreen({required this.ticketId, super.key});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
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
              color: AppColors.accent.withValues(alpha: 0.15),
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
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text2,
                          ),
                        ),
                        const SizedBox(height: 24),
                        RsDigitalTicket(ticket: ticket),
                        const SizedBox(height: 20),
                        TextButton(
                          onPressed: () => context.go(AppRoutes.rayonTickets),
                          child: Text(
                            l10n.ticketBackToTickets,
                            style: GoogleFonts.barlow(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accent,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          statusMeta.note,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.barlow(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.text3,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 20),
                        ShareCard(
                          title: l10n.ticketShareMatchTitle,
                          icon: Icons.sports_soccer_rounded,
                          message: ticket.matchTitle,
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
      message: l10n.ticketStatusPendingSubtitle,
      note: l10n.ticketStatusPendingNote,
      icon: Icons.hourglass_top_rounded,
      color: AppColors.rsGold,
    ),
    RsTicketStatus.valid => _TicketStatusMeta(
      title: l10n.ticketStatusValidTitle,
      message: l10n.ticketStatusValidSubtitle,
      note: l10n.ticketStatusValidNote,
      icon: Icons.check_rounded,
      color: AppColors.accent,
    ),
    RsTicketStatus.used => _TicketStatusMeta(
      title: l10n.ticketStatusUsedTitle,
      message: l10n.ticketStatusUsedSubtitle,
      note: l10n.ticketStatusUsedNote,
      icon: Icons.check_circle_outline_rounded,
      color: AppColors.text3,
    ),
    RsTicketStatus.cancelled => _TicketStatusMeta(
      title: l10n.ticketStatusCancelledTitle,
      message: l10n.ticketStatusCancelledSubtitle,
      note: l10n.ticketStatusCancelledNote,
      icon: Icons.block_rounded,
      color: AppColors.red,
    ),
  };
}
