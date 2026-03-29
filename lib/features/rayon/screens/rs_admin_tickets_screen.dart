import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../shared/widgets/cool_async_view.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_empty_view.dart';
import '../../../../shared/widgets/cool_skeleton.dart';
import '../providers/rayon_sports_provider.dart';
import '../models/rs_models.dart';
import '../providers/rs_admin_provider.dart';
import '../widgets/rs_admin_shell.dart';
import 'package:cool_app/core/l10n/l10n.dart';

/// Admin screen for managing RS tickets — view all, filter by match, update status.
class RsAdminTicketsScreen extends ConsumerStatefulWidget {
  const RsAdminTicketsScreen({super.key});

  @override
  ConsumerState<RsAdminTicketsScreen> createState() =>
      _RsAdminTicketsScreenState();
}

class _RsAdminTicketsScreenState extends ConsumerState<RsAdminTicketsScreen> {
  String? _selectedMatchId;
  String _statusFilter = 'all';

  static const _statusOptions = [
    'all',
    'pending',
    'valid',
    'used',
    'cancelled',
    'voided',
    'refunded',
  ];

  @override
  Widget build(BuildContext context) {
    final ticketsAsync = ref.watch(rsAdminTicketsProvider(_selectedMatchId));
    final matchesAsync = ref.watch(rsAdminMatchesProvider);

    return RsAdminShell(
      title: 'Tickets',
      subtitle:
          'Review issued tickets, control gate status, and resolve refunds from one command surface.',
      metrics: [
        RsAdminMetric(
          label: 'total',
          value:
              ticketsAsync.whenOrNull(data: (tickets) => '${tickets.length}') ??
              '...',
        ),
        RsAdminMetric(
          label: 'valid',
          value:
              ticketsAsync.whenOrNull(
                data: (tickets) =>
                    '${tickets.where((t) => t.status == TicketStatus.valid).length}',
              ) ??
              '...',
        ),
        RsAdminMetric(
          label: 'used',
          value:
              ticketsAsync.whenOrNull(
                data: (tickets) =>
                    '${tickets.where((t) => t.status == TicketStatus.used).length}',
              ) ??
              '...',
        ),
      ],
      controls: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Status filter chips
          SizedBox(
            height: 44,
            child:
                ticketsAsync.whenOrNull(
                  data: (tickets) {
                    final counts = <String, int>{};
                    for (final t in tickets) {
                      final s = t.status.name;
                      counts[s] = (counts[s] ?? 0) + 1;
                    }
                    return ListView(
                      scrollDirection: Axis.horizontal,
                      children: _statusOptions.map((s) {
                        final count = s == 'all'
                            ? tickets.length
                            : (counts[s] ?? 0);
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _FilterChip(
                            label:
                                '${s[0].toUpperCase()}${s.substring(1)} ($count)',
                            isSelected: _statusFilter == s,
                            onTap: () => setState(() => _statusFilter = s),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ) ??
                const SizedBox.shrink(),
          ),
          const SizedBox(height: 6),
          // Match filter
          matchesAsync.whenOrNull(
                data: (matches) => _MatchFilter(
                  matches: matches,
                  selected: _selectedMatchId,
                  onChanged: (id) => setState(() => _selectedMatchId = id),
                ),
              ) ??
              const SizedBox.shrink(),
        ],
      ),
      child: CoolAsyncView<List<RsTicket>>(
        value: ticketsAsync,
        onRetry: () => ref.invalidate(rsAdminTicketsProvider(_selectedMatchId)),
        loadingWidget: const Padding(
          padding: EdgeInsets.all(16),
          child: CoolSkeletonList(itemCount: 4),
        ),
        emptyCheck: (tickets) => tickets.isEmpty,
        emptyWidget: const CoolEmptyView(
          subtitle: 'No tickets found',
          icon: Icons.confirmation_number_outlined,
          isPremium: true,
        ),
        builder: (tickets) {
          final filtered = _statusFilter == 'all'
              ? tickets
              : tickets.where((t) => t.status.name == _statusFilter).toList();
          if (filtered.isEmpty) {
            return const CoolEmptyView(
              subtitle: 'No tickets match this filter',
              icon: Icons.filter_list_off_rounded,
              isPremium: true,
            );
          }
          return ListView.separated(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            separatorBuilder: (context, index) =>
                const SizedBox(height: CoolSpace.x2),
            itemBuilder: (context, index) {
              final ticket = filtered[index];
              return _TicketTile(
                ticket: ticket,
                onStatusChange: (status) => _updateStatus(ticket.id, status),
                onGateCheck: ticket.status == TicketStatus.valid
                    ? () => _gateCheck(ticket)
                    : null,
                onRefund:
                    (ticket.status == TicketStatus.pending ||
                        ticket.status == TicketStatus.valid)
                    ? () => _refundTicket(ticket)
                    : null,
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _updateStatus(String ticketId, String status) async {
    final repo = ref.read(rayonSportsRepositoryProvider);
    await repo.updateTicketStatus(ticketId, status: status);
    ref.invalidate(rsAdminTicketsProvider(_selectedMatchId));
  }

  Future<void> _gateCheck(RsTicket ticket) async {
    final colors = context.coolSemanticColors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.elevatedBackground,
        title: Text(
          'Gate Check',
          style: GoogleFonts.dmSans(
            fontWeight: FontWeight.w700,
            color: colors.primaryText,
          ),
        ),
        content: Text(
          'Mark this ticket as USED at the gate?\n\n'
          '${ticket.matchTitle}\n'
          '${ticket.seatType} · ${ticket.amountPaid} RWF',
          style: GoogleFonts.dmSans(color: colors.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.confirmEntry),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _updateStatus(ticket.id, 'used');
      if (mounted) {
        HapticFeedback.mediumImpact();
      }
    }
  }

  Future<void> _refundTicket(RsTicket ticket) async {
    final colors = context.coolSemanticColors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.elevatedBackground,
        title: Text(
          'Refund Ticket',
          style: GoogleFonts.dmSans(
            fontWeight: FontWeight.w700,
            color: colors.primaryText,
          ),
        ),
        content: Text(
          'Refund this ticket? This cannot be undone.\n\n'
          '${ticket.matchTitle}\n'
          '${ticket.seatType} · ${ticket.amountPaid} RWF',
          style: GoogleFonts.dmSans(color: colors.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.refund),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final repo = ref.read(rayonSportsRepositoryProvider);
      await repo.bulkRefundTickets([ticket.id]);
      ref.invalidate(rsAdminTicketsProvider(_selectedMatchId));
      if (mounted) {
        HapticFeedback.mediumImpact();
      }
    }
  }
}

class _MatchFilter extends StatelessWidget {
  const _MatchFilter({
    required this.matches,
    required this.selected,
    required this.onChanged,
  });
  final List<RsMatch> matches;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Ticket match filter Current',
      child: SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          children: [
            _FilterChip(
              label: 'All',
              isSelected: selected == null,
              onTap: () => onChanged(null),
            ),
            ...matches.map(
              (m) => Padding(
                padding: const EdgeInsets.only(left: 8),
                child: _FilterChip(
                  label: '${m.homeTeam} vs ${m.awayTeam}',
                  isSelected: selected == m.id,
                  onTap: () => onChanged(m.id),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Semantics(
      button: true,
      selected: isSelected,
      label: '$label filter',
      hint: 'Filter $label',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: isSelected
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF15498F), Color(0xFF0B2A63)],
                  )
                : LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [colors.cardSurfaceStrong, colors.cardSurface],
                  ),
            borderRadius: BorderRadius.circular(CoolRadii.pill),
            border: Border.all(
              color: isSelected ? RsColors.rsRed : colors.borderStrong,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isSelected ? Colors.white : colors.primaryText,
            ),
          ),
        ),
      ),
    );
  }
}

class _TicketTile extends StatelessWidget {
  const _TicketTile({
    required this.ticket,
    required this.onStatusChange,
    this.onGateCheck,
    this.onRefund,
  });
  final RsTicket ticket;
  final void Function(String status) onStatusChange;
  final VoidCallback? onGateCheck;
  final VoidCallback? onRefund;

  static const _statusFlow = ['pending', 'valid', 'used'];

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final dateStr = DateFormat('d MMM HH:mm').format(ticket.purchasedAt);
    final matchLabel = ticket.matchTitle.isNotEmpty
        ? ticket.matchTitle
        : 'Match ${ticket.matchId.substring(0, 8)}';
    return RepaintBoundary(
      child: Semantics(
        container: true,
        label:
            'Ticket for $matchLabel. Seat '
            '${ticket.amountPaid} Rwandan francs. Purchased $dateStr. '
            'Status ${ticket.status.name}.',
        child: CoolCard(
          backgroundColor: colors.cardSurfaceStrong,
          borderColor: colors.borderStrong,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      matchLabel,
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                  _StatusBadge(status: ticket.status.name),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${ticket.seatType} · ${ticket.amountPaid} RWF · $dateStr',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.secondaryText,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ..._statusFlow
                      .where((s) => s != ticket.status.name)
                      .map(
                        (s) => Semantics(
                          button: true,
                          label: 'Change ticket status to $s',
                          hint: 'Mark ticket $s',
                          excludeSemantics: true,
                          child: GestureDetector(
                            onTap: () => onStatusChange(s),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: colors.chipBackground,
                                borderRadius: BorderRadius.circular(
                                  CoolRadii.pill,
                                ),
                                border: Border.all(color: colors.border),
                              ),
                              child: Text(
                                '→ ${s.toUpperCase()}',
                                style: GoogleFonts.dmSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: colors.accent,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  if (onGateCheck != null)
                    _ActionChip(
                      icon: Icons.qr_code_scanner_rounded,
                      label: 'Gate Check',
                      color: colors.accent,
                      onTap: onGateCheck!,
                    ),
                  if (onRefund != null)
                    _ActionChip(
                      icon: Icons.undo_rounded,
                      label: 'Refund',
                      color: colors.danger,
                      onTap: onRefund!,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(CoolRadii.pill),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  Color _color(BuildContext context) {
    final colors = context.coolSemanticColors;
    return switch (status) {
      'valid' => colors.accent,
      'used' => colors.info,
      'cancelled' => colors.danger,
      'voided' => colors.tertiaryText,
      'refunded' => colors.teamSurface,
      _ => colors.warning,
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = _color(context);
    return Semantics(
      label: 'Status ${status.toLowerCase()}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(CoolRadii.pill),
            border: Border.all(color: c.withValues(alpha: 0.24)),
          ),
          child: Text(
            status.toUpperCase(),
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: c,
            ),
          ),
        ),
      ),
    );
  }
}
