import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/cool_async_view.dart';
import '../../../../shared/widgets/cool_empty_view.dart';
import '../../../../shared/widgets/cool_skeleton.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../widgets/partner_navigation.dart';
import '../models/rs_models.dart';
import '../providers/rs_admin_provider.dart';

/// Admin screen for managing RS matches — create, edit, toggle sale, delete.
class RsAdminMatchesScreen extends ConsumerStatefulWidget {
  const RsAdminMatchesScreen({super.key});

  @override
  ConsumerState<RsAdminMatchesScreen> createState() =>
      _RsAdminMatchesScreenState();
}

class _RsAdminMatchesScreenState extends ConsumerState<RsAdminMatchesScreen> {
  @override
  Widget build(BuildContext context) {
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
          'Matches',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        actions: buildPartnerAppBarActions(context, homeColor: Colors.white),
      ),
      floatingActionButton: Semantics(
        button: true,
        label: 'Add match',
        hint: 'Opens the new match form',
        child: FloatingActionButton(
          backgroundColor: AppColors.rsBlue,
          onPressed: () => _showMatchForm(context),
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
      body: CoolAsyncView<List<RsMatch>>(
        value: matchesAsync,
        onRetry: () => ref.invalidate(rsAdminMatchesProvider),
        loadingWidget: const Padding(
          padding: EdgeInsets.all(16),
          child: CoolSkeletonList(itemCount: 4),
        ),
        emptyCheck: (matches) => matches.isEmpty,
        emptyWidget: const CoolEmptyView(
          message: 'No matches have been scheduled yet.',
          icon: Icons.sports_soccer_outlined,
        ),
        builder: (matches) => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: matches.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final match = matches[index];
            return _MatchTile(
              match: match,
              onToggleSale: () => _toggleSale(match),
              onEdit: () => _showMatchForm(context, match: match),
              onDelete: () => _deleteMatch(match),
            );
          },
        ),
      ),
    );
  }

  Future<void> _toggleSale(RsMatch match) async {
    final repo = ref.read(rayonSportsRepositoryProvider);
    await repo.toggleMatchSale(match.id, isOnSale: !match.isOnSale);
    ref.invalidate(rsAdminMatchesProvider);
  }

  Future<void> _deleteMatch(RsMatch match) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Delete match?',
          style: GoogleFonts.dmSans(color: AppColors.text),
        ),
        content: Text(
          '${match.homeTeam} vs ${match.awayTeam}',
          style: GoogleFonts.dmSans(color: AppColors.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final repo = ref.read(rayonSportsRepositoryProvider);
    await repo.deleteMatch(match.id);
    ref.invalidate(rsAdminMatchesProvider);
  }

  void _showMatchForm(BuildContext context, {RsMatch? match}) {
    final isEdit = match != null;
    final homeCtrl = TextEditingController(
      text: match?.homeTeam ?? 'Rayon Sports',
    );
    final awayCtrl = TextEditingController(text: match?.awayTeam);
    final compCtrl = TextEditingController(text: match?.competition);
    final venueCtrl = TextEditingController(
      text: match?.venue ?? 'Amahoro Stadium',
    );
    final generalCtrl = TextEditingController(
      text: match?.ticketGeneralPrice.toString() ?? '2000',
    );
    final vipCtrl = TextEditingController(
      text: match?.ticketVipPrice.toString() ?? '5000',
    );
    final capacityCtrl = TextEditingController(
      text: match?.capacity.toString() ?? '20000',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isEdit ? 'Edit Match' : 'New Match',
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 16),
              _FormField(controller: homeCtrl, label: 'Home Team'),
              _FormField(controller: awayCtrl, label: 'Away Team'),
              _FormField(controller: compCtrl, label: 'Competition'),
              _FormField(controller: venueCtrl, label: 'Venue'),
              Row(
                children: [
                  Expanded(
                    child: _FormField(
                      controller: generalCtrl,
                      label: 'General Price',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FormField(
                      controller: vipCtrl,
                      label: 'VIP Price',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              _FormField(
                controller: capacityCtrl,
                label: 'Capacity',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.rsBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () async {
                  final repo = ref.read(rayonSportsRepositoryProvider);
                  if (isEdit) {
                    await repo.updateMatch(match.id, <String, dynamic>{
                      'home_team': homeCtrl.text,
                      'away_team': awayCtrl.text,
                      'competition': compCtrl.text,
                      'venue': venueCtrl.text,
                      'ticket_general_price':
                          int.tryParse(generalCtrl.text) ?? 2000,
                      'ticket_vip_price': int.tryParse(vipCtrl.text) ?? 5000,
                      'capacity': int.tryParse(capacityCtrl.text) ?? 20000,
                    });
                  } else {
                    await repo.createMatch(
                      homeTeam: homeCtrl.text,
                      awayTeam: awayCtrl.text,
                      competition: compCtrl.text,
                      venue: venueCtrl.text,
                      matchDate: DateTime.now().add(const Duration(days: 7)),
                      kickoffTime: '15:00',
                      ticketGeneralPrice:
                          int.tryParse(generalCtrl.text) ?? 2000,
                      ticketVipPrice: int.tryParse(vipCtrl.text) ?? 5000,
                      capacity: int.tryParse(capacityCtrl.text) ?? 20000,
                      saleStartsAt: DateTime.now(),
                    );
                  }
                  ref.invalidate(rsAdminMatchesProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(isEdit ? 'Update' : 'Create'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({
    required this.match,
    required this.onToggleSale,
    required this.onEdit,
    required this.onDelete,
  });
  final RsMatch match;
  final VoidCallback onToggleSale;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('d MMM yyyy').format(match.matchDate);
    return Semantics(
      container: true,
      label:
          'Match ${match.homeTeam} versus ${match.awayTeam}. '
          '${match.isOnSale ? 'On sale.' : 'Off sale.'} '
          '$dateStr at ${match.kickoffTime}. Venue ${match.venue}. '
          'General price ${match.ticketGeneralPrice} Rwandan francs. '
          'VIP price ${match.ticketVipPrice} Rwandan francs. Capacity ${match.capacity}.',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${match.homeTeam} vs ${match.awayTeam}',
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ),
                Semantics(
                  label: match.isOnSale ? 'Status on sale' : 'Status off sale',
                  child: ExcludeSemantics(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: match.isOnSale
                            ? AppColors.accent.withValues(alpha: 0.15)
                            : AppColors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        match.isOnSale ? 'ON SALE' : 'OFF SALE',
                        style: GoogleFonts.dmSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: match.isOnSale
                              ? AppColors.accent
                              : AppColors.red,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$dateStr · ${match.kickoffTime} · ${match.venue}',
              style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.text3),
            ),
            Text(
              '${match.competition} · Gen ${match.ticketGeneralPrice} RWF · VIP ${match.ticketVipPrice} RWF · Cap ${match.capacity}',
              style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.text3),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _TileAction(
                  icon: match.isOnSale ? Icons.pause : Icons.play_arrow,
                  label: match.isOnSale ? 'Pause' : 'Start',
                  onTap: onToggleSale,
                ),
                const SizedBox(width: 12),
                _TileAction(icon: Icons.edit, label: 'Edit', onTap: onEdit),
                const SizedBox(width: 12),
                _TileAction(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  onTap: onDelete,
                  color: AppColors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TileAction extends StatelessWidget {
  const _TileAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.text2;
    return Semantics(
      button: true,
      label: label,
      hint: 'Double tap to ${label.toLowerCase()} this match',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: c),
            const SizedBox(width: 4),
            Text(label, style: GoogleFonts.dmSans(fontSize: 11, color: c)),
          ],
        ),
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  const _FormField({
    required this.controller,
    required this.label,
    this.keyboardType,
  });
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        textField: true,
        label: label,
        hint: 'Double tap to enter $label',
        child: TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: GoogleFonts.dmSans(color: AppColors.text, fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: GoogleFonts.dmSans(
              color: AppColors.text3,
              fontSize: 13,
            ),
            filled: true,
            fillColor: AppColors.surface2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),
      ),
    );
  }
}
