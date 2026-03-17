import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/status/models/cool_activity.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../providers/admin_gamification_providers.dart';
import '../repositories/admin_gamification_repository.dart';
import '../../../core/l10n/l10n.dart';

/// Admin CRUD screen for managing token-earning activities.
class ManageActivitiesScreen extends ConsumerWidget {
  const ManageActivitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activitiesAsync = ref.watch(adminActivitiesProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: context.l10n.back,
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.text),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accent,
        onPressed: () => _showEditSheet(context, ref, null),
        child: const Icon(Icons.add_rounded, color: Colors.black),
      ),
      body: activitiesAsync.when(
        data: (activities) => activities.isEmpty
            ? Center(
                child: Text(
                  'No activities yet',
                  style:
                      GoogleFonts.dmSans(fontSize: 14, color: AppColors.text3),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 96),
                itemCount: activities.length + 1,
                separatorBuilder: (context, i) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Text(
                      'Activities',
                      style: GoogleFonts.dmSans(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                        height: 1.1,
                      ),
                    );
                  }
                  final activity = activities[index - 1];
                  return _ActivityAdminCard(
                    activity: activity,
                    onEdit: () => _showEditSheet(context, ref, activity),
                    onToggle: () => _toggleActive(context, ref, activity),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(context.l10n.genericErrorText(e.toString()),
              style: GoogleFonts.dmSans(color: AppColors.text3)),
        ),
      ),
    );
  }

  void _showEditSheet(
      BuildContext context, WidgetRef ref, CoolActivity? activity) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ActivityEditSheet(
        activity: activity,
        onSaved: () => ref.invalidate(adminActivitiesProvider),
      ),
    );
  }

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    CoolActivity activity,
  ) async {
    try {
      final repo =
          AdminGamificationRepository(client: Supabase.instance.client);
      await repo.toggleActivityActive(activity.id,
          isActive: !activity.isActive);
      ref.invalidate(adminActivitiesProvider);
      if (context.mounted) {
        CoolToast.success(
          context,
          activity.isActive
              ? '${activity.title} deactivated'
              : '${activity.title} activated',
        );
      }
    } catch (e) {
      if (context.mounted) CoolToast.error(context, 'Failed: $e');
    }
  }
}

// ─── Activity Card ──────────────────────────────────────────────────────

class _ActivityAdminCard extends StatelessWidget {
  const _ActivityAdminCard({
    required this.activity,
    required this.onEdit,
    required this.onToggle,
  });

  final CoolActivity activity;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
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
            child: Text(activity.emoji, style: const TextStyle(fontSize: 22)),
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
                        activity.title,
                        style: GoogleFonts.dmSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    _ActiveBadge(isActive: activity.isActive),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${_categoryLabel(activity.category)} · ${activity.tokensAwarded} Tokens',
                  style:
                      GoogleFonts.dmSans(fontSize: 12, color: AppColors.text3),
                ),
                if (activity.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    activity.description,
                    style: GoogleFonts.dmSans(
                        fontSize: 11, color: AppColors.text3),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              activity.isActive
                  ? Icons.toggle_on_rounded
                  : Icons.toggle_off_rounded,
              color: activity.isActive ? Colors.green : AppColors.text3,
              size: 32,
            ),
            onPressed: onToggle,
            tooltip: activity.isActive ? 'Deactivate' : 'Activate',
          ),
        ],
      ),
    );
  }

  static String _categoryLabel(String category) => switch (category) {
        'groups' => '💰 Groups',
        'rayon' => '⚽ Rayon',
        'mobility' => '🚗 Mobility',
        'social' => '📲 Social',
        'general' => '⭐ General',
        _ => category,
      };
}

// ─── Edit / Create Sheet ─────────────────────────────────────────────────

class _ActivityEditSheet extends StatefulWidget {
  const _ActivityEditSheet({this.activity, required this.onSaved});

  final CoolActivity? activity;
  final VoidCallback onSaved;

  @override
  State<_ActivityEditSheet> createState() => _ActivityEditSheetState();
}

class _ActivityEditSheetState extends State<_ActivityEditSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _emojiCtrl;
  late final TextEditingController _slugCtrl;
  late final TextEditingController _tokensCtrl;
  late final TextEditingController _sortCtrl;
  late String _category;
  late bool _isActive;
  bool _saving = false;

  bool get _isNew => widget.activity == null;

  static const _categories = [
    'groups',
    'rayon',
    'mobility',
    'social',
    'general',
  ];

  @override
  void initState() {
    super.initState();
    final a = widget.activity;
    _titleCtrl = TextEditingController(text: a?.title ?? '');
    _descCtrl = TextEditingController(text: a?.description ?? '');
    _emojiCtrl = TextEditingController(text: a?.emoji ?? '⭐');
    _slugCtrl = TextEditingController(text: a?.slug ?? '');
    _tokensCtrl =
        TextEditingController(text: a != null ? '${a.tokensAwarded}' : '20');
    _sortCtrl =
        TextEditingController(text: a != null ? '${a.sortOrder}' : '0');
    _category = a?.category ?? _categories.first;
    if (!_categories.contains(_category)) _category = 'general';
    _isActive = a?.isActive ?? true;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _emojiCtrl.dispose();
    _slugCtrl.dispose();
    _tokensCtrl.dispose();
    _sortCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty || _slugCtrl.text.trim().isEmpty) {
      CoolToast.error(context, 'Title and slug are required.');
      return;
    }

    setState(() => _saving = true);
    try {
      final data = <String, dynamic>{
        if (!_isNew) 'id': widget.activity!.id,
        'slug': _slugCtrl.text.trim(),
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'emoji': _emojiCtrl.text.trim().isEmpty ? '⭐' : _emojiCtrl.text.trim(),
        'category': _category,
        'tokens_awarded': int.tryParse(_tokensCtrl.text.trim()) ?? 20,
        'sort_order': int.tryParse(_sortCtrl.text.trim()) ?? 0,
        'is_active': _isActive,
      };

      final repo =
          AdminGamificationRepository(client: Supabase.instance.client);
      await repo.upsertActivity(data);

      widget.onSaved();
      if (mounted) {
        Navigator.of(context).pop();
        CoolToast.success(
          context,
          _isNew ? 'Activity created' : 'Activity updated',
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
                    _isNew ? 'Create Activity' : 'Edit Activity',
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
                      Text(context.l10n.active,
                          style: GoogleFonts.dmSans(
                              fontSize: 12, color: AppColors.text3)),
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
                _Field(label: 'Slug (unique key)', controller: _slugCtrl),
                _Field(
                    label: 'Description',
                    controller: _descCtrl,
                    maxLines: 2),
                _Field(label: 'Emoji', controller: _emojiCtrl),
                _DropdownField(
                  label: 'Category',
                  value: _category,
                  items: _categories,
                  onChanged: (v) => setState(() => _category = v),
                ),
                const SizedBox(height: 12),
                _Field(
                  label: 'Tokens Awarded',
                  controller: _tokensCtrl,
                  keyboardType: TextInputType.number,
                ),
                _Field(
                  label: 'Sort Order',
                  controller: _sortCtrl,
                  keyboardType: TextInputType.number,
                ),
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
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black),
                          )
                        : Text(
                            _isNew ? 'Create' : 'Save',
                            style: GoogleFonts.dmSans(
                                fontSize: 15, fontWeight: FontWeight.w700),
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
        style: GoogleFonts.dmSans(
            fontSize: 14,
            color: AppColors.text,
            fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          labelText: label,
          labelStyle:
              GoogleFonts.dmSans(fontSize: 13, color: AppColors.text3),
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
            borderSide:
                const BorderSide(color: AppColors.accent, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
        Text(label,
            style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.text3)),
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
                  .map((e) => DropdownMenuItem(
                      value: e, child: Text(e.replaceAll('_', ' '))))
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
