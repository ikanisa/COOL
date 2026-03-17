import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/cool_toast.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../models/group_detail.dart';
import '../../models/group_member.dart';
import '../../providers/groups_provider.dart';

// ═════════════════════════════════════════════════════════════════════════
// Group Settings Sheet (admin / creator only)
// ═════════════════════════════════════════════════════════════════════════

class GroupSettingsSheet extends ConsumerStatefulWidget {
  const GroupSettingsSheet({required this.detail, this.onDismiss, super.key});

  final GroupDetail detail;
  final VoidCallback? onDismiss;

  @override
  ConsumerState<GroupSettingsSheet> createState() => _GroupSettingsSheetState();
}

class _GroupSettingsSheetState extends ConsumerState<GroupSettingsSheet> {
  late TextEditingController _nameController;
  late TextEditingController _descController;
  late TextEditingController _targetController;
  late String _frequency;
  late String _visibility;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final group = widget.detail.group;
    _nameController = TextEditingController(text: group.name);
    _descController = TextEditingController(text: group.description ?? '');
    _targetController = TextEditingController(
      text: group.targetAmount.toString(),
    );
    _frequency = group.frequency ?? 'monthly';
    _visibility = group.visibility;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final groupId = widget.detail.group.id;
      if (groupId == null) return;

      final updates = <String, dynamic>{
        'name': _nameController.text.trim(),
        'description': _descController.text.trim(),
        'target_amount': int.tryParse(_targetController.text.trim()) ?? 0,
        'frequency': _frequency,
        'visibility': _visibility,
      };

      await ref
          .read(groupsProvider.notifier)
          .updateGroup(groupId, updates);

      widget.onDismiss?.call();
      if (mounted) {
        Navigator.of(context).pop();
        CoolToast.success(context, 'Group updated');
      }
    } catch (e) {
      if (mounted) {
        CoolToast.error(context, 'Failed to save: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showAddAdminSheet(
    BuildContext context,
    List<GroupMember> members,
    List<GroupMember> admins,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AdminSelectionSheet(
        groupId: widget.detail.group.id!,
        members: members,
        currentAdmins: admins,
      ),
    ).then((_) {
      // Refresh the group detail when sheet closes
      if (widget.detail.group.id != null) {
        ref.invalidate(groupDetailProvider(widget.detail.group.id!));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.read(currentUserProvider)?.id;
    final members = widget.detail.members;
    final admins = members.where((m) => m.isAdmin).toList();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border2,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Text(
                  'Group Settings',
                  style: GoogleFonts.dmSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 24),

                // ── Name ──
                const _SettingsLabel('Group name'),
                const SizedBox(height: 6),
                _SettingsInput(controller: _nameController),
                const SizedBox(height: 20),

                // ── Description ──
                const _SettingsLabel('Description'),
                const SizedBox(height: 6),
                _SettingsInput(
                  controller: _descController,
                  maxLines: 3,
                  hint: 'Optional description',
                ),
                const SizedBox(height: 20),

                // ── Target amount ──
                const _SettingsLabel('Target amount (RWF)'),
                const SizedBox(height: 6),
                _SettingsInput(
                  controller: _targetController,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 20),

                // ── Frequency ──
                const _SettingsLabel('Contribution frequency'),
                const SizedBox(height: 6),
                _FrequencySelector(
                  value: _frequency,
                  onChanged: (v) => setState(() => _frequency = v),
                ),
                const SizedBox(height: 20),

                // ── Visibility ──
                const _SettingsLabel('Visibility'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _SettingsToggle(
                      label: 'Private',
                      isSelected: _visibility == 'private',
                      onTap: () => setState(() => _visibility = 'private'),
                    ),
                    const SizedBox(width: 8),
                    _SettingsToggle(
                      label: 'Public',
                      isSelected: _visibility == 'public',
                      onTap: () => setState(() => _visibility = 'public'),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // ── Admins ──
                _SettingsLabel(
                  'Admins (${admins.length})',
                ),
                const SizedBox(height: 8),
                ...admins.map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.admin_panel_settings_outlined,
                          size: 18,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            a.displayName ?? '#${a.userId.substring(0, 6)}',
                            style: GoogleFonts.dmSans(
                              fontSize: 14,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        if (a.userId != currentUserId)
                          IconButton(
                            tooltip: 'Action',
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              size: 18,
                              color: AppColors.red,
                            ),
                            onPressed: () {
                              // TODO: remove admin
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => _showAddAdminSheet(context, members, admins),
                    icon: const Icon(
                      Icons.person_add_alt_1_rounded,
                      size: 18,
                      color: AppColors.accent,
                    ),
                    label: Text(
                      'Add admin',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
  
                  // ── Save ──
                  SizedBox(
                    width: double.infinity,
                    child: CoolButton(
                      label: 'Save changes',
                      isLoading: _isSaving,
                      onTap: _saveChanges,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    }
  }

// ── Tiny helper widgets for settings ──

class _SettingsLabel extends StatelessWidget {
  const _SettingsLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.dmSans(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.text2,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _SettingsInput extends StatelessWidget {
  const _SettingsInput({
    required this.controller,
    this.maxLines = 1,
    this.hint,
    this.keyboardType,
  });

  final TextEditingController controller;
  final int maxLines;
  final String? hint;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.text),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.dmSans(fontSize: 13, color: AppColors.text3),
        filled: true,
        fillColor: AppColors.surface2,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
      ),
    );
  }
}

class _FrequencySelector extends StatelessWidget {
  const _FrequencySelector({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = ['daily', 'weekly', 'monthly'];
    return Row(
      children: [
        for (final opt in options) ...[
          _SettingsToggle(
            label: opt[0].toUpperCase() + opt.substring(1),
            isSelected: value == opt,
            onTap: () => onChanged(opt),
          ),
          if (opt != options.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _SettingsToggle extends StatelessWidget {
  const _SettingsToggle({
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accentGlow : AppColors.surface2,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.border,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? AppColors.accent : AppColors.text2,
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Admin Selection Sheet
// ═════════════════════════════════════════════════════════════════════════

class _AdminSelectionSheet extends ConsumerStatefulWidget {
  const _AdminSelectionSheet({
    required this.groupId,
    required this.members,
    required this.currentAdmins,
  });

  final String groupId;
  final List<GroupMember> members;
  final List<GroupMember> currentAdmins;

  @override
  ConsumerState<_AdminSelectionSheet> createState() => _AdminSelectionSheetState();
}

class _AdminSelectionSheetState extends ConsumerState<_AdminSelectionSheet> {
  bool _isSaving = false;

  Future<void> _makeAdmin(GroupMember member) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      await ref.read(groupsProvider.notifier).addGroupAdmin(
            groupId: widget.groupId,
            userId: member.userId,
          );
      if (mounted) {
        Navigator.of(context).pop();
        CoolToast.success(context, '${member.displayName ?? 'User'} is now an admin');
      }
    } catch (e) {
      if (mounted) {
        CoolToast.error(context, 'Failed to add admin: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Filter out existing admins
    final adminIds = widget.currentAdmins.map((a) => a.userId).toSet();
    final eligibleMembers = widget.members.where((m) => !adminIds.contains(m.userId)).toList();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Text(
                  'Add Admin',
                  style: GoogleFonts.dmSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Text(
                  'Select a member to grant admin access.',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: AppColors.text2,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (eligibleMembers.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      'All members are already admins.',
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        color: AppColors.text3,
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                    itemCount: eligibleMembers.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final member = eligibleMembers[index];
                      return Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: AppColors.surface2,
                            child: Icon(Icons.person, size: 18, color: AppColors.text2),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  member.displayName ?? 'Unknown',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.text,
                                  ),
                                ),
                                Text(
                                  '#${member.userId.substring(0, 8)}',
                                  style: GoogleFonts.dmMono(
                                    fontSize: 12,
                                    color: AppColors.text3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          CoolButton(
                            label: 'Add',
                            variant: CoolButtonVariant.secondary,
                            fullWidth: false,
                            isLoading: _isSaving,
                            onTap: () => _makeAdmin(member),
                          ),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
