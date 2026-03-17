import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/status/models/cool_mission.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../providers/admin_gamification_providers.dart';
import '../repositories/admin_gamification_repository.dart';

/// Admin CRUD screen for managing cooperative missions.
class ManageMissionsScreen extends ConsumerWidget {
  const ManageMissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missionsAsync = ref.watch(adminMissionsProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Back',
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.text),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accent,
        onPressed: () => _showEditSheet(context, ref, null),
        child: const Icon(Icons.add_rounded, color: Colors.black),
      ),
      body: missionsAsync.when(
        data: (missions) => missions.isEmpty
            ? Center(
                child: Text(
                  'No missions yet',
                  style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.text3),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 96),
                itemCount: missions.length + 1,
                separatorBuilder: (context, i) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Text(
                      'Missions',
                      style: GoogleFonts.dmSans(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                        height: 1.1,
                      ),
                    );
                  }
                  final mission = missions[index - 1];
                  return _MissionAdminCard(
                    mission: mission,
                    onEdit: () => _showEditSheet(context, ref, mission),
                    onToggle: () => _toggleActive(context, ref, mission),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Error: $e', style: GoogleFonts.dmSans(color: AppColors.text3)),
        ),
      ),
    );
  }

  void _showEditSheet(BuildContext context, WidgetRef ref, CoolMission? mission) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _MissionEditSheet(
        mission: mission,
        onSaved: () => ref.invalidate(adminMissionsProvider),
      ),
    );
  }

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    CoolMission mission,
  ) async {
    try {
      final repo = AdminGamificationRepository(client: Supabase.instance.client);
      await repo.toggleMissionActive(mission.id, isActive: !mission.isActive);
      ref.invalidate(adminMissionsProvider);
      if (context.mounted) {
        CoolToast.success(
          context,
          mission.isActive ? '${mission.title} deactivated' : '${mission.title} activated',
        );
      }
    } catch (e) {
      if (context.mounted) CoolToast.error(context, 'Failed: $e');
    }
  }
}

// ─── Mission Card ──────────────────────────────────────────────────────────

class _MissionAdminCard extends StatelessWidget {
  const _MissionAdminCard({
    required this.mission,
    required this.onEdit,
    required this.onToggle,
  });

  final CoolMission mission;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd MMM yyyy');
    return CoolCard(
      onTap: onEdit,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(mission.emoji, style: const TextStyle(fontSize: 22)),
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
                        mission.title,
                        style: GoogleFonts.dmSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    _ActiveBadge(isActive: mission.isActive),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${mission.missionType.displayLabel} · ${mission.scope.name} · '
                  '${dateFmt.format(mission.startsAt)} – ${dateFmt.format(mission.endsAt)}',
                  style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.text3),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Target: ${mission.targetValue} · Reward: ${mission.rewardPoints} Tokens',
                  style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.text3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              mission.isActive ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
              color: mission.isActive ? Colors.green : AppColors.text3,
              size: 32,
            ),
            onPressed: onToggle,
            tooltip: mission.isActive ? 'Deactivate' : 'Activate',
          ),
        ],
      ),
    );
  }
}

// ─── Edit / Create Sheet ─────────────────────────────────────────────────

class _MissionEditSheet extends StatefulWidget {
  const _MissionEditSheet({this.mission, required this.onSaved});

  final CoolMission? mission;
  final VoidCallback onSaved;

  @override
  State<_MissionEditSheet> createState() => _MissionEditSheetState();
}

class _MissionEditSheetState extends State<_MissionEditSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _emojiCtrl;
  late final TextEditingController _targetCtrl;
  late final TextEditingController _rewardPtsCtrl;
  late final TextEditingController _rewardDescCtrl;
  late final TextEditingController _scopeIdCtrl;
  late String _missionType;
  late String _scopeType;
  late DateTime _startsAt;
  late DateTime _endsAt;
  late bool _isActive;
  bool _saving = false;

  bool get _isNew => widget.mission == null;

  static const _missionTypes = [
    'savings_sprint',
    'supporter_season',
    'commuter_week',
    'matchday_month',
  ];

  static const _scopeTypes = ['global', 'group', 'chapter'];

  @override
  void initState() {
    super.initState();
    final m = widget.mission;
    _titleCtrl = TextEditingController(text: m?.title ?? '');
    _descCtrl = TextEditingController(text: m?.description ?? '');
    _emojiCtrl = TextEditingController(text: m?.emoji ?? '🎯');
    _targetCtrl = TextEditingController(text: m != null ? '${m.targetValue}' : '');
    _rewardPtsCtrl = TextEditingController(text: m != null ? '${m.rewardPoints}' : '0');
    _rewardDescCtrl = TextEditingController(text: m?.rewardDescription ?? '');
    _scopeIdCtrl = TextEditingController(text: m?.scopeId ?? '');
    _missionType = m?.missionType.value ?? _missionTypes.first;
    // Normalize camelCase to snake_case for the dropdown
    if (!_missionTypes.contains(_missionType)) {
      _missionType = _missionTypes.first;
    }
    _scopeType = m?.scope.value ?? 'global';
    if (!_scopeTypes.contains(_scopeType)) _scopeType = 'global';
    _startsAt = m?.startsAt ?? DateTime.now();
    _endsAt = m?.endsAt ?? DateTime.now().add(const Duration(days: 14));
    _isActive = m?.isActive ?? true;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _emojiCtrl.dispose();
    _targetCtrl.dispose();
    _rewardPtsCtrl.dispose();
    _rewardDescCtrl.dispose();
    _scopeIdCtrl.dispose();
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
    if (_titleCtrl.text.trim().isEmpty || _targetCtrl.text.trim().isEmpty) {
      CoolToast.error(context, 'Title and target value are required.');
      return;
    }

    setState(() => _saving = true);
    try {
      final data = <String, dynamic>{
        if (!_isNew) 'id': widget.mission!.id,
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'emoji': _emojiCtrl.text.trim().isEmpty ? '🎯' : _emojiCtrl.text.trim(),
        'mission_type': _missionType,
        'target_value': int.tryParse(_targetCtrl.text.trim()) ?? 0,
        'scope_type': _scopeType,
        'scope_id': _scopeIdCtrl.text.trim().isEmpty ? null : _scopeIdCtrl.text.trim(),
        'starts_at': _startsAt.toIso8601String(),
        'ends_at': _endsAt.toIso8601String(),
        'reward_points': int.tryParse(_rewardPtsCtrl.text.trim()) ?? 0,
        'reward_description':
            _rewardDescCtrl.text.trim().isEmpty ? null : _rewardDescCtrl.text.trim(),
        'is_active': _isActive,
      };

      final repo = AdminGamificationRepository(client: Supabase.instance.client);
      await repo.upsertMission(data);

      widget.onSaved();
      if (mounted) {
        Navigator.of(context).pop();
        CoolToast.success(
          context,
          _isNew ? 'Mission created' : 'Mission updated',
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
    final dateFmt = DateFormat('dd MMM yyyy');
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      decoration: BoxDecoration(
        color: AppColors.bg,
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
              color: AppColors.border,
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
                    _isNew ? 'Create Mission' : 'Edit Mission',
                    style: GoogleFonts.dmSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                ),
                if (!_isNew)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Active', style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.text3)),
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
                _Field(label: 'Description', controller: _descCtrl, maxLines: 2),
                _Field(label: 'Emoji', controller: _emojiCtrl),
                _DropdownField(
                  label: 'Mission Type',
                  value: _missionType,
                  items: _missionTypes,
                  onChanged: (v) => setState(() => _missionType = v),
                ),
                const SizedBox(height: 12),
                _Field(
                  label: 'Target Value',
                  controller: _targetCtrl,
                  keyboardType: TextInputType.number,
                ),
                _DropdownField(
                  label: 'Scope',
                  value: _scopeType,
                  items: _scopeTypes,
                  onChanged: (v) => setState(() => _scopeType = v),
                ),
                const SizedBox(height: 12),
                _Field(label: 'Scope ID (optional)', controller: _scopeIdCtrl),
                // Date pickers
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
                _Field(
                  label: 'Reward Points',
                  controller: _rewardPtsCtrl,
                  keyboardType: TextInputType.number,
                ),
                _Field(label: 'Reward Description', controller: _rewardDescCtrl),
                const SizedBox(height: 16),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
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

class _ActiveBadge extends StatelessWidget {
  const _ActiveBadge({required this.isActive});
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isActive
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isActive ? 'Active' : 'Inactive',
        style: GoogleFonts.dmSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isActive ? Colors.green : Colors.red,
        ),
      ),
    );
  }
}

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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.text3)),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
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
    this.keyboardType,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.text, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.dmSans(fontSize: 13, color: AppColors.text3),
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.text3)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: AppColors.surface,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                color: AppColors.text,
                fontWeight: FontWeight.w500,
              ),
              items: items
                  .map((e) => DropdownMenuItem(value: e, child: Text(e.replaceAll('_', ' '))))
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
