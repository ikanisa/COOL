import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/cool_foundations.dart';
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
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final theme = Theme.of(context);
    final borderColor = _statusBorderColor(ticket.status, colors);
    final statusColor = _statusDotColor(ticket.status, colors);
    final qrSize = isExpanded ? 126.0 : 74.0;
    final isGateReady = ticket.status == RsTicketStatus.valid;
    final statusNote = switch (ticket.status) {
      RsTicketStatus.pending =>
        'Payment is still pending confirmation. Your QR unlocks automatically after SMS reconciliation confirms the charge.',
      RsTicketStatus.valid => 'Present this QR at the gate for entry.',
      RsTicketStatus.used => 'This ticket has already been used.',
      RsTicketStatus.cancelled ||
      RsTicketStatus.voided ||
      RsTicketStatus.refunded =>
        'This ticket was cancelled and can no longer be used.',
    };

    return Semantics(
      label:
          '${ticket.matchTitle}. ${ticket.seatType.value} seat.'
          'Status: ${ticket.status.label}. ${ticket.venue}.',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radii.md),
          boxShadow: CoolShadows.floating(theme.brightness, strength: 0.72),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: RsColors.rsCardGradient,
            borderRadius: BorderRadius.circular(radii.md),
            border: Border.all(color: borderColor),
          ),
          padding: EdgeInsets.all(space.x5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ticket.competition.toUpperCase(),
                style: text.rayon(
                  theme.textTheme.labelSmall,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: RsColors.rsGoldLight,
                ),
              ),
              SizedBox(height: space.x2),
              Text(
                ticket.matchTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.rayonCondensed(
                  isExpanded
                      ? theme.textTheme.titleLarge
                      : theme.textTheme.titleSmall,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  color: RsColors.rsWhite,
                ),
              ),
              SizedBox(height: space.x1 + 2),
              Text(
                ticket.venue,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.rayon(
                  theme.textTheme.bodySmall,
                  fontWeight: FontWeight.w700,
                  color: colors.secondaryText,
                ),
              ),
              SizedBox(height: space.x1),
              Text(
                '${DateFormat('EEE, d MMM').format(ticket.matchDate)} • ${ticket.kickoffTime}',
                style: text.mono(
                  theme.textTheme.labelSmall,
                  fontWeight: FontWeight.w700,
                  color: RsColors.rsBluePale,
                ),
              ),
              SizedBox(height: space.x3 + 2),
              Wrap(
                spacing: space.x2,
                runSpacing: space.x2,
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
                      color: RsColors.rsWhite,
                      borderRadius: BorderRadius.circular(radii.sm),
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
                                color: RsColors.rsBlue,
                              ),
                              dataModuleStyle: const QrDataModuleStyle(
                                color: RsColors.rsBlue,
                              ),
                            )
                          : _LockedQrPlaceholder(status: ticket.status),
                    ),
                  ),
                  SizedBox(width: space.x4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ticket.momoReference,
                          style: text.mono(
                            theme.textTheme.labelSmall,
                            fontWeight: FontWeight.w700,
                            color: RsColors.rsGoldLight,
                          ),
                        ),
                        SizedBox(height: space.x2),
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
                              style: text.rayon(
                                theme.textTheme.labelSmall,
                                fontWeight: FontWeight.w700,
                                color: RsColors.rsWhite,
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
              SizedBox(height: space.x3),
              Text(
                statusNote,
                style: text.rayon(
                  theme.textTheme.bodySmall,
                  fontWeight: FontWeight.w700,
                  color: colors.secondaryText,
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
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: space.x3, vertical: space.x2),
      decoration: BoxDecoration(
        color: colors.overlaySurface.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(radii.sm),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: text.rayon(
              Theme.of(context).textTheme.labelSmall,
              fontWeight: FontWeight.w700,
              color: colors.secondaryText,
            ),
          ),
          SizedBox(height: space.x1),
          Text(
            value,
            style: text.mono(
              Theme.of(context).textTheme.labelSmall,
              fontWeight: FontWeight.w700,
              color: RsColors.rsWhite,
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
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final radii = context.coolRadii;
    final space = context.coolSpace;
    final icon = switch (status) {
      RsTicketStatus.pending => Icons.hourglass_top_rounded,
      RsTicketStatus.used => Icons.check_circle_outline_rounded,
      RsTicketStatus.cancelled ||
      RsTicketStatus.voided ||
      RsTicketStatus.refunded => Icons.block_rounded,
      RsTicketStatus.valid => Icons.qr_code_rounded,
    };

    final label = switch (status) {
      RsTicketStatus.pending => 'PENDING',
      RsTicketStatus.used => 'USED',
      RsTicketStatus.cancelled || RsTicketStatus.voided => 'CANCELLED',
      RsTicketStatus.refunded => 'REFUNDED',
      RsTicketStatus.valid => 'READY',
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong,
        borderRadius: BorderRadius.circular(radii.sm),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: colors.tertiaryText, size: 26),
          SizedBox(height: space.x2),
          Text(
            label,
            style: text.mono(
              Theme.of(context).textTheme.labelSmall,
              fontWeight: FontWeight.w700,
              color: colors.tertiaryText,
            ),
          ),
        ],
      ),
    );
  }
}

Color _statusBorderColor(RsTicketStatus status, CoolSemanticColors colors) =>
    switch (status) {
      RsTicketStatus.valid => colors.accent.withValues(alpha: 0.55),
      RsTicketStatus.used => colors.cardSurfaceStrong,
      RsTicketStatus.cancelled ||
      RsTicketStatus.voided ||
      RsTicketStatus.refunded => colors.danger.withValues(alpha: 0.45),
      RsTicketStatus.pending => RsColors.rsBlueBorder,
    };

Color _statusDotColor(RsTicketStatus status, CoolSemanticColors colors) =>
    switch (status) {
      RsTicketStatus.valid => colors.accent,
      RsTicketStatus.used => colors.tertiaryText,
      RsTicketStatus.cancelled ||
      RsTicketStatus.voided ||
      RsTicketStatus.refunded => colors.danger,
      RsTicketStatus.pending => RsColors.rsGoldLight,
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
