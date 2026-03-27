import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/cool_foundations.dart';
import '../../../../shared/widgets/cool_bottom_sheet.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/cool_toast.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../models/group_detail.dart';
import '../../models/group_member.dart';
import '../../providers/groups_provider.dart';

part 'group_settings_sheet_parts.dart';

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
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  late final TextEditingController _targetController;
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

      await ref.read(groupsProvider.notifier).updateGroup(groupId, updates);

      widget.onDismiss?.call();
      if (!mounted) return;
      Navigator.of(context).pop();
      CoolToast.success(context, 'Group updated');
    } catch (error) {
      if (!mounted) return;
      CoolToast.error(context, 'Failed to save: $error');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _removeAdmin(GroupMember member) async {
    final groupId = widget.detail.group.id;
    if (groupId == null) return;

    try {
      await ref
          .read(groupsProvider.notifier)
          .removeGroupAdmin(groupId: groupId, userId: member.userId);
      if (!mounted) return;
      ref.invalidate(groupDetailProvider(groupId));
      CoolToast.success(
        context,
        '${member.displayName ?? 'User'} removed as admin',
      );
    } catch (error) {
      if (!mounted) return;
      CoolToast.error(context, 'Failed to remove admin: $error');
    }
  }

  void _showAddAdminSheet(
    BuildContext context,
    List<GroupMember> members,
    List<GroupMember> admins,
  ) {
    final groupId = widget.detail.group.id;
    if (groupId == null) return;

    showCoolBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AdminSelectionSheet(
        groupId: groupId,
        members: members,
        currentAdmins: admins,
      ),
    ).then((_) {
      ref.invalidate(groupDetailProvider(groupId));
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final currentUserId = ref.read(currentUserProvider)?.id;
    final members = widget.detail.members;
    final admins = members.where((member) => member.isAdmin).toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SheetHandle(),
              SizedBox(height: space.x5),
              Text(
                'Group settings',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.primaryText,
                ),
              ),
              SizedBox(height: space.x2),
              Text(
                'Update contribution rules, visibility, and admin access.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.secondaryText,
                  height: 1.45,
                ),
              ),
              SizedBox(height: space.x6),
              const _SettingsLabel('Group name'),
              SizedBox(height: space.x2),
              _SettingsInput(controller: _nameController),
              SizedBox(height: space.x5),
              const _SettingsLabel('Description'),
              SizedBox(height: space.x2),
              _SettingsInput(
                controller: _descController,
                maxLines: 3,
                hint: 'Optional description',
              ),
              SizedBox(height: space.x5),
              const _SettingsLabel('Target amount (RWF)'),
              SizedBox(height: space.x2),
              _SettingsInput(
                controller: _targetController,
                keyboardType: TextInputType.number,
              ),
              SizedBox(height: space.x5),
              const _SettingsLabel('Contribution frequency'),
              SizedBox(height: space.x2),
              _FrequencySelector(
                value: _frequency,
                onChanged: (value) => setState(() => _frequency = value),
              ),
              SizedBox(height: space.x5),
              const _SettingsLabel('Visibility'),
              SizedBox(height: space.x2),
              Row(
                children: [
                  Expanded(
                    child: _SettingsToggle(
                      label: 'Private',
                      isSelected: _visibility == 'private',
                      onTap: () => setState(() => _visibility = 'private'),
                    ),
                  ),
                  SizedBox(width: space.x2),
                  Expanded(
                    child: _SettingsToggle(
                      label: 'Public',
                      isSelected: _visibility == 'public',
                      onTap: () => setState(() => _visibility = 'public'),
                    ),
                  ),
                ],
              ),
              SizedBox(height: space.x6),
              _SettingsLabel('Admins (${admins.length})'),
              SizedBox(height: space.x3),
              ...admins.map(
                (admin) => Padding(
                  padding: EdgeInsets.only(bottom: space.x2),
                  child: _AdminRow(
                    member: admin,
                    isCurrentUser: admin.userId == currentUserId,
                    onRemove: admin.userId == currentUserId
                        ? null
                        : () => _removeAdmin(admin),
                  ),
                ),
              ),
              SizedBox(height: space.x2),
              TextButton.icon(
                onPressed: () => _showAddAdminSheet(context, members, admins),
                icon: Icon(
                  Icons.person_add_alt_1_rounded,
                  size: 18,
                  color: colors.accent,
                ),
                label: Text(
                  'Add admin',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.accent,
                  ),
                ),
              ),
              SizedBox(height: space.x7),
              CoolButton(
                label: 'Save changes',
                isLoading: _isSaving,
                onTap: _saveChanges,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
