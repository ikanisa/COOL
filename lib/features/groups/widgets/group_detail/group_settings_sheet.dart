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

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: colors.borderStrong,
          borderRadius: BorderRadius.all(Radius.circular(radii.xs)),
        ),
      ),
    );
  }
}

class _SettingsLabel extends StatelessWidget {
  const _SettingsLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: colors.secondaryText,
        letterSpacing: 0.2,
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
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: colors.primaryText,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: theme.textTheme.bodySmall?.copyWith(
          color: colors.tertiaryText,
        ),
        filled: true,
        fillColor: colors.inputSurface,
        contentPadding: EdgeInsets.symmetric(
          horizontal: space.x4,
          vertical: space.x3,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(radii.sm)),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(radii.sm)),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(radii.sm)),
          borderSide: BorderSide(color: colors.accent, width: 1.5),
        ),
      ),
    );
  }
}

class _FrequencySelector extends StatelessWidget {
  const _FrequencySelector({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = ['daily', 'weekly', 'monthly'];
    return Wrap(
      spacing: CoolSpace.x2,
      runSpacing: CoolSpace.x2,
      children: [
        for (final option in options)
          _SettingsToggle(
            label: option[0].toUpperCase() + option.substring(1),
            isSelected: value == option,
            onTap: () => onChanged(option),
          ),
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
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: isSelected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.all(Radius.circular(radii.pill)),
          onTap: onTap,
          child: AnimatedContainer(
            duration: CoolMotion.quick,
            curve: CoolMotion.enterCurve,
            constraints: const BoxConstraints(
              minHeight: CoolTapTargets.minimum,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: CoolSpace.x4,
              vertical: CoolSpace.x3,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? colors.chipSelectedBackground
                  : colors.chipBackground,
              borderRadius: BorderRadius.all(Radius.circular(radii.pill)),
              border: Border.all(
                color: isSelected ? colors.accent : colors.border,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: isSelected ? colors.accent : colors.secondaryText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminRow extends StatelessWidget {
  const _AdminRow({
    required this.member,
    required this.isCurrentUser,
    this.onRemove,
  });

  final GroupMember member;
  final bool isCurrentUser;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final resolvedName = member.displayName ?? _shortUserId(member.userId, 6);

    return Container(
      padding: const EdgeInsets.all(CoolSpace.x3),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.sm)),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: colors.chipBackground,
            child: Icon(Icons.person, size: 18, color: colors.secondaryText),
          ),
          const SizedBox(width: CoolSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  resolvedName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
                Text(
                  _shortUserId(member.userId),
                  style: text.mono(
                    theme.textTheme.labelSmall,
                    color: colors.tertiaryText,
                  ),
                ),
              ],
            ),
          ),
          if (isCurrentUser)
            Text(
              'You',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.secondaryText,
              ),
            )
          else
            IconButton(
              tooltip: 'Remove admin',
              icon: Icon(
                Icons.remove_circle_outline,
                size: 20,
                color: colors.danger,
              ),
              onPressed: onRemove,
            ),
        ],
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
  ConsumerState<_AdminSelectionSheet> createState() =>
      _AdminSelectionSheetState();
}

class _AdminSelectionSheetState extends ConsumerState<_AdminSelectionSheet> {
  bool _isSaving = false;

  Future<void> _makeAdmin(GroupMember member) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      await ref
          .read(groupsProvider.notifier)
          .addGroupAdmin(groupId: widget.groupId, userId: member.userId);
      if (!mounted) return;
      Navigator.of(context).pop();
      CoolToast.success(
        context,
        '${member.displayName ?? 'User'} is now an admin',
      );
    } catch (error) {
      if (!mounted) return;
      CoolToast.error(context, 'Failed to add admin: $error');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final adminIds = widget.currentAdmins.map((admin) => admin.userId).toSet();
    final eligibleMembers = widget.members
        .where((member) => !adminIds.contains(member.userId))
        .toList();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SheetHandle(),
          SizedBox(height: space.x5),
          Text(
            'Add admin',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: colors.primaryText,
            ),
          ),
          SizedBox(height: space.x2),
          Text(
            'Select a member to grant admin access.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
            ),
          ),
          SizedBox(height: space.x4),
          if (eligibleMembers.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'All members are already admins.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.tertiaryText,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.symmetric(vertical: space.x1),
                itemCount: eligibleMembers.length,
                separatorBuilder: (_, _) => SizedBox(height: space.x3),
                itemBuilder: (context, index) {
                  final member = eligibleMembers[index];
                  return Container(
                    padding: const EdgeInsets.all(CoolSpace.x3),
                    decoration: BoxDecoration(
                      color: colors.cardSurface,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(CoolRadii.sm),
                      ),
                      border: Border.all(color: colors.border),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: colors.chipBackground,
                          child: Icon(
                            Icons.person,
                            size: 18,
                            color: colors.secondaryText,
                          ),
                        ),
                        const SizedBox(width: CoolSpace.x3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                member.displayName ?? 'Unknown',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colors.primaryText,
                                ),
                              ),
                              Text(
                                _shortUserId(member.userId),
                                style: text.mono(
                                  theme.textTheme.labelSmall,
                                  color: colors.tertiaryText,
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
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

String _shortUserId(String userId, [int length = 8]) {
  final end = userId.length < length ? userId.length : length;
  return '#${userId.substring(0, end)}';
}
