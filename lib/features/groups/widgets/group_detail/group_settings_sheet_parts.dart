part of 'group_settings_sheet.dart';

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
