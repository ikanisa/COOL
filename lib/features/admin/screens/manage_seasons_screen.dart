import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/status/models/cool_season.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../providers/admin_gamification_providers.dart';
import '../repositories/admin_gamification_repository.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';
import '../../../shared/widgets/cool_screen_background.dart';

/// Admin CRUD screen for managing seasons (live-ops campaigns).
class ManageSeasonsScreen extends ConsumerWidget {
  const ManageSeasonsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.coolPalette;
    final seasonsAsync = ref.watch(adminSeasonsProvider);

    return CoolScreenBackground(


      showGlow: false,


      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: context.l10n.back,
          icon: Icon(Icons.arrow_back_rounded, color: palette.text),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: palette.accent,
        onPressed: () => _showEditSheet(context, ref, null),
        child: const Icon(Icons.add_rounded, color: Colors.black),
      ),
      body: seasonsAsync.when(
        data: (seasons) => seasons.isEmpty
            ? Center(
                child: Text(
                  'No seasons yet',
                  style: GoogleFonts.dmSans(fontSize: 14, color: palette.text3),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 96),
                itemCount: seasons.length + 1,
                separatorBuilder: (context, i) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Text(
                      'Seasons',
                      style: GoogleFonts.dmSans(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: palette.text,
                        height: 1.1,
                      ),
                    );
                  }
                  final season = seasons[index - 1];
                  return _SeasonAdminCard(
                    season: season,
                    onEdit: () => _showEditSheet(context, ref, season),
                    onToggle: () => _toggleActive(context, ref, season),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(context.l10n.genericErrorText(e.toString()), style: GoogleFonts.dmSans(color: palette.text3)),
        ),
      ),
    ),


    );
  }

  void _showEditSheet(BuildContext context, WidgetRef ref, CoolSeason? season) {
    showCoolBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SeasonEditSheet(
        season: season,
        repo: ref.read(adminGamificationRepositoryProvider),
        onSaved: () => ref.invalidate(adminSeasonsProvider),
      ),
    );
  }

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    CoolSeason season,
  ) async {
    try {
      final repo = ref.read(adminGamificationRepositoryProvider);
      await repo.toggleSeasonActive(season.id, isActive: !season.isActive);
      ref.invalidate(adminSeasonsProvider);
      if (context.mounted) {
        CoolToast.success(
          context,
          season.isActive ? '${season.title} deactivated' : '${season.title} activated',
        );
      }
    } catch (e) {
      if (context.mounted) CoolToast.error(context, 'Failed: $e');
    }
  }
}

// ─── Season Card ──────────────────────────────────────────────────────────

class _SeasonAdminCard extends StatelessWidget {
  const _SeasonAdminCard({
    required this.season,
    required this.onEdit,
    required this.onToggle,
  });

  final CoolSeason season;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final dateFmt = DateFormat('dd MMM yyyy');
    final statusLabel = season.isLive
        ? 'Live'
        : season.isUpcoming
            ? 'Upcoming'
            : season.isExpired
                ? 'Ended'
                : season.isActive
                    ? 'Active'
                    : 'Inactive';
    final statusColor = season.isLive
        ? Colors.green
        : season.isUpcoming
            ? Colors.orange
            : Colors.red;

    return CoolCard(
      onTap: onEdit,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(season.emoji, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        season.title,
                        style: GoogleFonts.dmSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: palette.text,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusLabel,
                        style: GoogleFonts.dmSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${season.theme} · ${dateFmt.format(season.startsAt)} – ${dateFmt.format(season.endsAt)}',
                  style: GoogleFonts.dmSans(fontSize: 12, color: palette.text3),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              season.isActive ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
              color: season.isActive ? Colors.green : palette.text3,
              size: 32,
            ),
            onPressed: onToggle,
            tooltip: season.isActive ? 'Deactivate' : 'Activate',
          ),
        ],
      ),
    );
  }
}

// ─── Edit / Create Sheet ─────────────────────────────────────────────────

class _SeasonEditSheet extends StatefulWidget {
  const _SeasonEditSheet({this.season, required this.repo, required this.onSaved});

  final CoolSeason? season;
  final AdminGamificationRepository repo;
  final VoidCallback onSaved;

  @override
  State<_SeasonEditSheet> createState() => _SeasonEditSheetState();
}

class _SeasonEditSheetState extends State<_SeasonEditSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _emojiCtrl;
  late final TextEditingController _rewardsCtrl;
  late String _theme;
  late DateTime _startsAt;
  late DateTime _endsAt;
  late bool _isActive;
  bool _saving = false;

  bool get _isNew => widget.season == null;

  static const _themes = ['savings', 'supporter', 'commuter', 'matchday'];

  @override
  void initState() {
    super.initState();
    final s = widget.season;
    _titleCtrl = TextEditingController(text: s?.title ?? '');
    _emojiCtrl = TextEditingController(text: s?.emoji ?? '🏅');
    _rewardsCtrl = TextEditingController(text: s?.rewardsDescription ?? '');
    _theme = s?.theme ?? _themes.first;
    if (!_themes.contains(_theme)) _theme = _themes.first;
    _startsAt = s?.startsAt ?? DateTime.now();
    _endsAt = s?.endsAt ?? DateTime.now().add(const Duration(days: 28));
    _isActive = s?.isActive ?? false;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _emojiCtrl.dispose();
    _rewardsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final initial = isStart ? _startsAt : _endsAt;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startsAt = picked;
        } else {
          _endsAt = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      CoolToast.error(context, 'Title is required.');
      return;
    }

    setState(() => _saving = true);
    try {
      final data = <String, dynamic>{
        if (!_isNew) 'id': widget.season!.id,
        'title': _titleCtrl.text.trim(),
        'theme': _theme,
        'emoji': _emojiCtrl.text.trim().isEmpty ? '🏅' : _emojiCtrl.text.trim(),
        'starts_at': _startsAt.toIso8601String(),
        'ends_at': _endsAt.toIso8601String(),
        'is_active': _isActive,
        'rewards_description':
            _rewardsCtrl.text.trim().isEmpty ? null : _rewardsCtrl.text.trim(),
      };

      final repo = widget.repo;
      await repo.upsertSeason(data);

      widget.onSaved();
      if (mounted) {
        Navigator.of(context).pop();
        CoolToast.success(
          context,
          _isNew ? 'Season created' : 'Season updated',
        );
      }
    } catch (e) {
      if (mounted) CoolToast.error(context, 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final dateFmt = DateFormat('dd MMM yyyy');
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: palette.border,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _isNew ? 'Create Season' : 'Edit Season',
                    style: GoogleFonts.dmSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: palette.text,
                    ),
                  ),
                ),
                if (!_isNew)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(context.l10n.active, style: GoogleFonts.dmSans(fontSize: 12, color: palette.text3)),
                      const SizedBox(width: 4),
                      Switch.adaptive(
                        value: _isActive,
                        activeTrackColor: Colors.green,
                        onChanged: (v) => setState(() => _isActive = v),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
              shrinkWrap: true,
              children: [
                _Field(label: 'Title', controller: _titleCtrl),
                _Field(label: 'Emoji', controller: _emojiCtrl),
                _DropdownField(
                  label: 'Theme',
                  value: _theme,
                  items: _themes,
                  onChanged: (v) => setState(() => _theme = v),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _DateButton(
                        label: 'Starts',
                        value: dateFmt.format(_startsAt),
                        onTap: () => _pickDate(true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DateButton(
                        label: 'Ends',
                        value: dateFmt.format(_endsAt),
                        onTap: () => _pickDate(false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _Field(label: 'Rewards Description', controller: _rewardsCtrl, maxLines: 2),
                const SizedBox(height: 16),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : Text(
                            _isNew ? 'Create' : 'Save',
                            style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared reusable widgets ─────────────────────────────────────────────

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GoogleFonts.dmSans(fontSize: 11, color: palette.text3)),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: palette.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: GoogleFonts.dmSans(fontSize: 14, color: palette.text, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.dmSans(fontSize: 13, color: palette.text3),
          filled: true,
          fillColor: palette.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: palette.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: palette.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: palette.accent, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }
}

class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.dmSans(fontSize: 12, color: palette.text3)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: palette.surface,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                color: palette.text,
                fontWeight: FontWeight.w500,
              ),
              items: items
                  .map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(e[0].toUpperCase() + e.substring(1)),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}