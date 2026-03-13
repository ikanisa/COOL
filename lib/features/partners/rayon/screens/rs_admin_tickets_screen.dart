import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../widgets/partner_navigation.dart';
import '../models/rs_models.dart';
import '../providers/rs_admin_provider.dart';

/// Admin screen for managing RS tickets — view all, filter by match, update status.
class RsAdminTicketsScreen extends ConsumerStatefulWidget {
  const RsAdminTicketsScreen({super.key});

  @override
  ConsumerState<RsAdminTicketsScreen> createState() =>
      _RsAdminTicketsScreenState();
}

class _RsAdminTicketsScreenState extends ConsumerState<RsAdminTicketsScreen> {
  String? _selectedMatchId;

  @override
  Widget build(BuildContext context) {
    final ticketsAsync = ref.watch(rsAdminTicketsProvider(_selectedMatchId));
    final matchesAsync = ref.watch(rsAdminMatchesProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.rsBlue,
        elevation: 0,
        leading: buildPartnerBackButton(
          context,
          fallbackLocation: AppRoutes.adminRayon,
          color: Colors.white,
        ),
        title: Text(
          'Tickets',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        actions: buildPartnerAppBarActions(context, homeColor: Colors.white),
      ),
      body: Column(
        children: [
          // ── Match filter ──
          matchesAsync.whenOrNull(
                data: (matches) => _MatchFilter(
                  matches: matches,
                  selected: _selectedMatchId,
                  onChanged: (id) => setState(() => _selectedMatchId = id),
                ),
              ) ??
              const SizedBox.shrink(),
          // ── Ticket list ──
          Expanded(
            child: ticketsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Error: $e',
                  style: const TextStyle(color: AppColors.red),
                ),
              ),
              data: (tickets) {
                if (tickets.isEmpty) {
                  return Center(
                    child: Text(
                      'No tickets found',
                      style: GoogleFonts.dmSans(color: AppColors.text3),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: tickets.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final ticket = tickets[index];
                    return _TicketTile(
                      ticket: ticket,
                      onStatusChange: (status) =>
                          _updateStatus(ticket.id, status),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateStatus(String ticketId, String status) async {
    final repo = ref.read(rayonSportsRepositoryProvider);
    await repo.updateTicketStatus(ticketId, status: status);
    ref.invalidate(rsAdminTicketsProvider(_selectedMatchId));
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
    return SizedBox(
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
    return GestureDetector(
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
    );
  }
}

class _TicketTile extends StatelessWidget {
  const _TicketTile({required this.ticket, required this.onStatusChange});
  final RsTicket ticket;
  final void Function(String status) onStatusChange;

  static const _statusFlow = ['pending', 'valid', 'used'];

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('d MMM HH:mm').format(ticket.purchasedAt);
    return Container(
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
                  ticket.matchTitle.isNotEmpty
                      ? ticket.matchTitle
                      : 'Match ${ticket.matchId.substring(0, 8)}',
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
            children: _statusFlow
                .where((s) => s != ticket.status.name)
                .map(
                  (s) => GestureDetector(
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
                )
                .toList(),
          ),
        ],
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
    _ => AppColors.yellow,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}
