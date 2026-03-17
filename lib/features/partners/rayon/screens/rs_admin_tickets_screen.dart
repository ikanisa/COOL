import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/cool_async_view.dart';
import '../../../../shared/widgets/cool_empty_view.dart';
import '../../../../shared/widgets/cool_skeleton.dart';
import '../../providers/rayon_sports_provider.dart';
import '../models/rs_models.dart';
import '../providers/rs_admin_provider.dart';
import '../widgets/rs_admin_shell.dart';

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

  static const _statusOptions = ['all', 'pending', 'valid', 'used', 'cancelled', 'voided', 'refunded'];

  @override
  Widget build(BuildContext context) {
    final ticketsAsync = ref.watch(rsAdminTicketsProvider(_selectedMatchId));
    final matchesAsync = ref.watch(rsAdminMatchesProvider);

    return RsAdminShell(
      title: 'Tickets',
      subtitle: 'Review issued tickets, gate check & refund',
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
            height: 36,
            child: ticketsAsync.whenOrNull(
              data: (tickets) {
                final counts = <String, int>{};
                for (final t in tickets) {
                  final s = t.status.name;
                  counts[s] = (counts[s] ?? 0) + 1;
                }
                return ListView(
                  scrollDirection: Axis.horizontal,
                  children: _statusOptions.map((s) {
                    final count = s == 'all' ? tickets.length : (counts[s] ?? 0);
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _FilterChip(
                        label: '${s[0].toUpperCase()}${s.substring(1)} ($count)',
                        isSelected: _statusFilter == s,
                        onTap: () => setState(() => _statusFilter = s),
                      ),
                    );
                  }).toList(),
                );
              },
            ) ?? const SizedBox.shrink(),
          ),
          const SizedBox(height: 6),
          // Match filter
          matchesAsync.whenOrNull(
            data: (matches) => _MatchFilter(
              matches: matches,
              selected: _selectedMatchId,
              onChanged: (id) => setState(() => _selectedMatchId = id),
            ),
          ) ?? const SizedBox.shrink(),
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
            itemCount: filtered.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final ticket = filtered[index];
              return _TicketTile(
                ticket: ticket,
                onStatusChange: (status) => _updateStatus(ticket.id, status),
                onGateCheck: ticket.status == TicketStatus.valid
                    ? () => _gateCheck(ticket)
                    : null,
                onRefund: (ticket.status == TicketStatus.pending ||
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Gate Check',
          style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: AppColors.text),
        ),
        content: Text(
          'Mark this ticket as USED at the gate?\n\n'
          '${ticket.matchTitle}\n'
          '${ticket.seatType} · ${ticket.amountPaid} RWF',
          style: GoogleFonts.dmSans(color: AppColors.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Entry'),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Refund Ticket',
          style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: AppColors.text),
        ),
        content: Text(
          'Refund this ticket? This cannot be undone.\n\n'
          '${ticket.matchTitle}\n'
          '${ticket.seatType} · ${ticket.amountPaid} RWF',
          style: GoogleFonts.dmSans(color: AppColors.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Refund'),
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
    return Semantics(
      button: true,
      selected: isSelected,
      label: '$label filter',
      hint: 'Filter $label',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.rsBlue : AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? AppColors.rsBlue : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isSelected ? Colors.white : AppColors.text2,
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
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    matchLabel,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ),
                _StatusBadge(status: ticket.status.name),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${ticket.seatType} · ${ticket.amountPaid} RWF · $dateStr',
              style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.text3),
            ),
            const SizedBox(height: 8),
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
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surface2,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '→ $s',
                              style: GoogleFonts.dmSans(
                                fontSize: 11,
                                color: AppColors.accent,
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
                    color: AppColors.accent,
                    onTap: onGateCheck!,
                  ),
                if (onRefund != null)
                  _ActionChip(
                    icon: Icons.undo_rounded,
                    label: 'Refund',
                    color: AppColors.red,
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
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

  Color get _color => switch (status) {
    'valid' => AppColors.accent,
    'used' => AppColors.blue,
    'cancelled' => AppColors.red,
    'voided' => AppColors.text3,
    'refunded' => AppColors.purple,
    _ => AppColors.yellow,
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Status ${status.toLowerCase()}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            status.toUpperCase(),
            style: GoogleFonts.dmSans(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _color,
            ),
          ),
        ),
      ),
    );
  }
}
