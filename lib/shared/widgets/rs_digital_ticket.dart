import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/rs_colors.dart';
import '../../features/partners/rayon/models/rs_models.dart';

class RsDigitalTicket extends StatelessWidget {
  const RsDigitalTicket({
    required this.ticket,
    this.isExpanded = true,
    super.key,
  });

  final RsTicket ticket;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    final borderColor = _statusBorderColor(ticket.status);
    final statusColor = _statusDotColor(ticket.status);
    final qrSize = isExpanded ? 126.0 : 74.0;
    final isGateReady = ticket.status == RsTicketStatus.valid;
    final statusNote = switch (ticket.status) {
      RsTicketStatus.pending =>
        'Payment is still pending confirmation. Your QR unlocks automatically after SMS reconciliation confirms the charge.',
      RsTicketStatus.valid => 'Present this QR at the gate for entry.',
      RsTicketStatus.used => 'This ticket has already been used.',
      RsTicketStatus.cancelled =>
        'This ticket was cancelled and can no longer be used.',
    };

    return Semantics(
      label:
          '${ticket.matchTitle}. ${ticket.seatType.value} seat. '
          'Status: ${ticket.status.label}. ${ticket.venue}.',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 26,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: RsColors.rsCardGradient,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor),
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ticket.competition.toUpperCase(),
                style: GoogleFonts.barlow(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: AppColors.rsGoldLight,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                ticket.matchTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.barlow(
                  fontSize: isExpanded ? 22 : 18,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  color: AppColors.rsWhite,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                ticket.venue,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.barlow(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${DateFormat('EEE, d MMM').format(ticket.matchDate)} • ${ticket.kickoffTime}',
                style: GoogleFonts.dmMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.rsBluePale,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TicketChip(label: 'Seat', value: ticket.seatType.value),
                  _TicketChip(label: 'Fan ID', value: _fanIdFor(ticket)),
                  _TicketChip(
                    label: 'Price',
                    value: _formatRwf(ticket.amountPaid),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.rsWhite,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: SizedBox(
                      width: qrSize,
                      height: qrSize,
                      child: isGateReady
                          ? QrImageView(
                              data: ticket.qrData,
                              version: QrVersions.auto,
                              size: qrSize,
                              backgroundColor: Colors.transparent,
                              eyeStyle: const QrEyeStyle(
                                color: AppColors.rsBlue,
                              ),
                              dataModuleStyle: const QrDataModuleStyle(
                                color: AppColors.rsBlue,
                              ),
                            )
                          : _LockedQrPlaceholder(status: ticket.status),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ticket.momoReference,
                          style: GoogleFonts.dmMono(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.rsGoldLight,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              ticket.status.label.toUpperCase(),
                              style: GoogleFonts.barlow(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.rsWhite,
                                letterSpacing: 0.7,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                statusNote,
                style: GoogleFonts.barlow(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text2,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TicketChip extends StatelessWidget {
  const _TicketChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.barlow(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.text2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.dmMono(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.rsWhite,
            ),
          ),
        ],
      ),
    );
  }
}

class _LockedQrPlaceholder extends StatelessWidget {
  const _LockedQrPlaceholder({required this.status});

  final RsTicketStatus status;

  @override
  Widget build(BuildContext context) {
    final icon = switch (status) {
      RsTicketStatus.pending => Icons.hourglass_top_rounded,
      RsTicketStatus.used => Icons.check_circle_outline_rounded,
      RsTicketStatus.cancelled => Icons.block_rounded,
      RsTicketStatus.valid => Icons.qr_code_rounded,
    };

    final label = switch (status) {
      RsTicketStatus.pending => 'PENDING',
      RsTicketStatus.used => 'USED',
      RsTicketStatus.cancelled => 'CANCELLED',
      RsTicketStatus.valid => 'READY',
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.text3, size: 26),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.dmMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.text3,
            ),
          ),
        ],
      ),
    );
  }
}

Color _statusBorderColor(RsTicketStatus status) => switch (status) {
  RsTicketStatus.valid => AppColors.accent.withValues(alpha: 0.55),
  RsTicketStatus.used => AppColors.surface3,
  RsTicketStatus.cancelled => AppColors.red.withValues(alpha: 0.45),
  RsTicketStatus.pending => AppColors.rsBlueBorder,
};

Color _statusDotColor(RsTicketStatus status) => switch (status) {
  RsTicketStatus.valid => AppColors.accent,
  RsTicketStatus.used => AppColors.text3,
  RsTicketStatus.cancelled => AppColors.red,
  RsTicketStatus.pending => AppColors.rsGoldLight,
};

String _fanIdFor(RsTicket ticket) {
  final explicit = ticket.fanId.trim();
  if (explicit.isNotEmpty) {
    return explicit;
  }
  final userId = ticket.userId.trim();
  if (userId.length >= 8) {
    return userId.substring(0, 8).toUpperCase();
  }
  return userId.toUpperCase();
}

String _formatRwf(int amount) {
  return '${NumberFormat.decimalPattern('en').format(amount)} RWF';
}
