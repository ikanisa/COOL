import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/deep_link_config.dart';
import '../../../../core/models/engagement_event.dart';
import '../../../../core/providers/engagement_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/rs_digital_ticket.dart';
import '../../../../shared/widgets/share_card.dart';
import '../../rayon/models/rs_models.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../widgets/rayon_screen_scaffold.dart';
import '../../widgets/rayon_state_views.dart';

class TicketConfirmationScreen extends ConsumerStatefulWidget {
  const TicketConfirmationScreen({required this.ticketId, super.key});

  final String ticketId;

  @override
  ConsumerState<TicketConfirmationScreen> createState() =>
      _TicketConfirmationScreenState();
}

class _TicketConfirmationScreenState
    extends ConsumerState<TicketConfirmationScreen> {
  bool _issuingWallet = false;

  Future<void> _handleAddToWallet(RsTicket ticket) async {
    if (_issuingWallet) {
      return;
    }

    setState(() => _issuingWallet = true);

    final tracker = ref.read(engagementTrackerProvider);
    final crashlytics = ref.read(crashlyticsServiceProvider);
    final performance = ref.read(performanceServiceProvider);

    await tracker.track(
      EngagementEvent(
        name: EngagementEventName.walletAddStarted,
        parameters: <String, Object?>{
          'ticket_id': ticket.id,
          'match_id': ticket.matchId,
          'seat_type': ticket.seatType,
        },
      ),
    );

    performance.startTrace('wallet_add_ticket');

    try {
      final saveUrl = await ref
          .read(rayonSportsRepositoryProvider)
          .createGoogleWalletSaveUrl(ticketId: ticket.id);
      final uri = Uri.tryParse(saveUrl);
      if (uri == null) {
        throw StateError('Wallet save link is invalid.');
      }

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw StateError('Google Wallet could not be opened on this device.');
      }

      await performance.stopTrace(
        'wallet_add_ticket',
        attributes: <String, String>{'status': 'success'},
      );
      await tracker.track(
        EngagementEvent(
          name: EngagementEventName.walletAddCompleted,
          parameters: <String, Object?>{
            'ticket_id': ticket.id,
            'match_id': ticket.matchId,
          },
        ),
      );
    } catch (error, stackTrace) {
      await performance.stopTrace(
        'wallet_add_ticket',
        attributes: <String, String>{
          'status': 'error',
          'error': error.runtimeType.toString(),
        },
      );
      await crashlytics.recordError(
        error,
        stackTrace: stackTrace,
        reason: 'wallet_add_ticket',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is StateError
                  ? error.message.toString()
                  : 'Unable to open Google Wallet right now.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _issuingWallet = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticketAsync = ref.watch(rayonTicketByIdProvider(widget.ticketId));
    final notifier = ref.read(rayonSportsProvider.notifier);

    return RayonScreenScaffold(
      title: 'Ticket Status',
      scrollable: false,
      child: ticketAsync.when(
        data: (ticket) {
          if (ticket == null) {
            return RayonErrorView(
              message: 'Ticket not found.',
              onRetry: notifier.load,
            );
          }

          final statusMeta = _statusMeta(ticket.status);

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
                        Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.accent.withValues(alpha: 0.15),
                                border: Border.all(
                                  color: statusMeta.color.withValues(
                                    alpha: 0.4,
                                  ),
                                  width: 2,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                statusMeta.icon,
                                size: 40,
                                color: statusMeta.color,
                              ),
                            )
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
                        if (ticket.status == RsTicketStatus.valid) ...[
                          CoolButton(
                            label: 'Add to Google Wallet',
                            onTap: () => _handleAddToWallet(ticket),
                            isLoading: _issuingWallet,
                            icon: Icons.wallet_outlined,
                          ),
                          const SizedBox(height: 10),
                        ],
                        TextButton(
                          onPressed: () =>
                              context.go('/partners/rayon-sports/tickets'),
                          child: Text(
                            'Back to Tickets',
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
                          title: 'Share this match',
                          emoji: '⚽',
                          subtitle: ticket.matchTitle,
                          shareUrl: DeepLinkConfig.matchUri(
                            ticket.matchId,
                          ).toString(),
                          shareText: 'Check out ${ticket.matchTitle} on Cool!',
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
        error: (error, _) =>
            RayonErrorView(message: error.toString(), onRetry: notifier.load),
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

_TicketStatusMeta _statusMeta(RsTicketStatus status) => switch (status) {
  RsTicketStatus.pending => const _TicketStatusMeta(
    title: 'Payment Pending',
    subtitle: 'We are waiting for MTN MoMo confirmation before enabling entry.',
    note: 'Your QR unlocks automatically after the backend confirms payment.',
    icon: Icons.hourglass_top_rounded,
    color: AppColors.rsGold,
  ),
  RsTicketStatus.valid => const _TicketStatusMeta(
    title: 'Ticket Confirmed',
    subtitle: 'Your match entry is ready to use at the gate.',
    note:
        'A WhatsApp confirmation will also be sent to your registered number.',
    icon: Icons.check_rounded,
    color: AppColors.accent,
  ),
  RsTicketStatus.used => const _TicketStatusMeta(
    title: 'Ticket Used',
    subtitle: 'This ticket has already been scanned for entry.',
    note: 'Used tickets stay in your history but cannot be scanned again.',
    icon: Icons.check_circle_outline_rounded,
    color: AppColors.text3,
  ),
  RsTicketStatus.cancelled => const _TicketStatusMeta(
    title: 'Ticket Cancelled',
    subtitle: 'This ticket is no longer valid for gate access.',
    note: 'Contact support if this cancellation looks incorrect.',
    icon: Icons.block_rounded,
    color: AppColors.red,
  ),
};
