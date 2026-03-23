import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../shared/widgets/cool_async_view.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_empty_view.dart';
import '../../../../shared/widgets/cool_skeleton.dart';
import '../../providers/rayon_sports_provider.dart';
import '../models/rs_models.dart';
import '../providers/rs_admin_provider.dart';
import '../widgets/rs_admin_shell.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../shared/widgets/cool_bottom_sheet.dart';

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

    return RsAdminShell(
      title: context.l10n.matches1,
      subtitle:
          'Schedule fixtures, adjust pricing, and control sale status with one operational board.',
      floatingActionButton: Semantics(
        button: true,
        label: 'Add match',
        hint: 'New match',
        child: FloatingActionButton(
          backgroundColor: RsColors.rsBlue,
          onPressed: () => _showMatchForm(context),
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
      metrics: [
        RsAdminMetric(
          label: 'scheduled',
          value:
              matchesAsync.whenOrNull(data: (matches) => '${matches.length}') ??
              '...',
        ),
        RsAdminMetric(
          label: 'on sale',
          value:
              matchesAsync.whenOrNull(
                data: (matches) =>
                    '${matches.where((match) => match.isOnSale).length}',
              ) ??
              '...',
        ),
      ],
      child: CoolAsyncView<List<RsMatch>>(
        value: matchesAsync,
        onRetry: () => ref.invalidate(rsAdminMatchesProvider),
        loadingWidget: const Padding(
          padding: EdgeInsets.all(16),
          child: CoolSkeletonList(itemCount: 4),
        ),
        emptyCheck: (matches) => matches.isEmpty,
        emptyWidget: const CoolEmptyView(
          subtitle: 'No matches have yet',
          icon: Icons.sports_soccer_outlined,
          isPremium: true,
        ),
        builder: (matches) => ListView.separated(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
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
        backgroundColor: colors.elevatedBackground,
        title: Text(
          'Delete match?',
          style: GoogleFonts.dmSans(color: colors.primaryText),
        ),
        content: Text(
          '${match.homeTeam} vs ${match.awayTeam}',
          style: GoogleFonts.dmSans(color: colors.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              context.l10n.delete,
              style: TextStyle(color: colors.danger),
            ),
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
    final palette = context.coolPalette;
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

    showCoolBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.surface,
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
                  color: palette.text,
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
                  backgroundColor: RsColors.rsBlue,
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
    final colors = context.coolSemanticColors;
    final dateStr = DateFormat('d MMM yyyy').format(match.matchDate);
    return Semantics(
      container: true,
      label:
          'Match ${match.homeTeam} versus ${match.awayTeam}.'
          '${match.isOnSale ? 'On sale.' : 'Off sale.'} '
          '$dateStr at ${match.kickoffTime}. Venue ${match.venue}. '
          'General price ${match.ticketGeneralPrice} Rwandan francs. '
          'VIP price ${match.ticketVipPrice} Rwandan francs. Capacity ${match.capacity}.',
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
                    '${match.homeTeam} vs ${match.awayTeam}',
                    style: GoogleFonts.dmSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: colors.primaryText,
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
                            ? colors.accent.withValues(alpha: 0.15)
                            : colors.danger.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(CoolRadii.sm),
                      ),
                      child: Text(
                        match.isOnSale ? 'ON SALE' : 'OFF SALE',
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: match.isOnSale ? colors.accent : colors.danger,
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
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.secondaryText,
              ),
            ),
            Text(
              '${match.competition} Gen ${match.ticketGeneralPrice} RWF',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colors.secondaryText,
              ),
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
                  color: colors.danger,
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
    final colors = context.coolSemanticColors;
    final c = color ?? colors.secondaryText;
    return Semantics(
      button: true,
      label: label,
      hint: '${label.toLowerCase()} match',
      excludeSemantics: true,
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
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: CoolSpace.x3,
                vertical: CoolSpace.x2,
              ),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(CoolRadii.pill),
                border: Border.all(color: c.withValues(alpha: 0.18)),
              ),
              child: Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: c,
                ),
              ),
            ),
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
    final palette = context.coolPalette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        textField: true,
        label: label,
        hint: 'Enter $label',
        child: TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: GoogleFonts.dmSans(color: palette.text, fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: GoogleFonts.dmSans(color: palette.text3, fontSize: 13),
            filled: true,
            fillColor: palette.surface2,
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
