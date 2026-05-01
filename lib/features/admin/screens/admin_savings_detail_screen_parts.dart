part of 'admin_savings_detail_screen.dart';

extension _AdminSavingsDetailScreenView on _AdminSavingsDetailScreenState {
  Widget _buildGroupDetail(Map<String, dynamic> group) {
    final name = group['name']?.toString() ?? 'Unnamed';
    final description = group['description']?.toString();
    final targetAmount = _AdminSavingsDetailScreenState._asInt(
      group['target_amount'],
    );
    final monthlyContribution = _AdminSavingsDetailScreenState._asInt(
      group['monthly_contribution'],
    );
    final totalCollected = _AdminSavingsDetailScreenState._asInt(
      group['total_collected'],
    );
    final frequency = group['frequency']?.toString() ?? 'monthly';
    final inviteCode = group['invite_code']?.toString() ?? '';
    final isClosed = group['is_closed'] == true;
    final members = _AdminSavingsDetailScreenState._parseGroups(
      group['members'],
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: CoolSpace.x7),
      children: [
        SavingsGroupHeaderCard(
          name: name,
          description: description,
          targetAmount: targetAmount,
          monthlyContribution: monthlyContribution,
          totalCollected: totalCollected,
          frequency: frequency,
          inviteCode: inviteCode,
          isClosed: isClosed,
          onCloseGroup: isClosed
              ? null
              : () => _handleCloseGroup(group['id']?.toString()),
        ),
        const SizedBox(height: CoolSpace.x5),
        SavingsDetailTabBar(activeTab: _activeTab, onTabSelected: _selectTab),
        const SizedBox(height: CoolSpace.x4),
        switch (_activeTab) {
          SavingsDetailTab.members => _buildMembers(
            members,
            group['id']?.toString() ?? '',
          ),
          SavingsDetailTab.allocations => _buildAllocations(
            members,
            group['id']?.toString() ?? '',
          ),
        },
      ],
    );
  }

  Widget _buildMembers(List<Map<String, dynamic>> members, String groupId) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: CoolSpace.x3),
        CoolCard(
          backgroundColor: colors.operationalSurface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _addMemberPhoneController,
                      keyboardType: TextInputType.phone,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.primaryText,
                      ),
                      decoration: InputDecoration(
                        hintText: '+250788...',
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.tertiaryText,
                        ),
                        prefixIcon: Icon(
                          CoolIcons.phone,
                          size: 18,
                          color: colors.tertiaryText,
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 36,
                        ),
                        filled: true,
                        fillColor: colors.chipBackground,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(CoolRadii.sm),
                          borderSide: BorderSide.none,
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _addMemberNameController,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.primaryText,
                      ),
                      decoration: InputDecoration(
                        hintText: context.l10n.adminSavingsHintName,
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.tertiaryText,
                        ),
                        prefixIcon: Icon(
                          CoolIcons.profile,
                          size: 18,
                          color: colors.tertiaryText,
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 36,
                        ),
                        filled: true,
                        fillColor: colors.chipBackground,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(CoolRadii.sm),
                          borderSide: BorderSide.none,
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CoolSpace.x3),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isAddingMember
                      ? null
                      : () => _handleAddMemberByPhone(groupId),
                  icon: const Icon(CoolIcons.personAdd, size: 16),
                  label: Text(
                    _isAddingMember
                        ? context.l10n.adminSavingsAddingMember
                        : context.l10n.adminSavingsAddMember,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(CoolRadii.sm),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: CoolSpace.x4),
        if (members.isEmpty)
          CoolEmptyView(
            message: context.l10n.adminSavingsNoMembersYet,
            icon: CoolIcons.people,
          )
        else
          for (final member in members) ...[
            SavingsMemberRow(
              displayName: member['display_name']?.toString() ?? 'Member',
              phone: member['phone']?.toString(),
              onRemove: () => _handleRemoveMember(
                groupId,
                member['user_id']?.toString() ?? '',
                member['display_name']?.toString() ?? 'this member',
              ),
            ),
            const SizedBox(height: CoolSpace.x2),
          ],
      ],
    );
  }

  Widget _buildAllocations(List<Map<String, dynamic>> members, String groupId) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: CoolSpace.x3),
        CoolCard(
          backgroundColor: colors.operationalSurface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (members.isEmpty)
                const CoolEmptyView(
                  message: 'No members',
                  icon: CoolIcons.people,
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colors.chipBackground,
                    borderRadius: BorderRadius.circular(CoolRadii.sm),
                  ),
                  child: DropdownButton<String>(
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    value: _selectedMemberUserId,
                    icon: Icon(
                      CoolIcons.unfoldMore,
                      size: 18,
                      color: colors.tertiaryText,
                    ),
                    hint: Row(
                      children: [
                        Icon(
                          CoolIcons.person,
                          size: 18,
                          color: colors.tertiaryText,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          context.l10n.adminSavingsSelectMember,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.tertiaryText,
                          ),
                        ),
                      ],
                    ),
                    dropdownColor: colors.cardSurface,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.primaryText,
                    ),
                    items: members.map((m) {
                      final userId = m['user_id']?.toString() ?? '';
                      final name = m['display_name']?.toString() ?? 'Member';
                      return DropdownMenuItem(value: userId, child: Text(name));
                    }).toList(),
                    onChanged: _selectMemberUserId,
                  ),
                ),
              const SizedBox(height: CoolSpace.x3),
              TextField(
                controller: _allocationAmountController,
                keyboardType: TextInputType.number,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.primaryText,
                ),
                decoration: InputDecoration(
                  hintText: context.l10n.adminSavingsHintAmount,
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.tertiaryText,
                  ),
                  prefixIcon: Icon(
                    CoolIcons.paymentsFilled,
                    size: 18,
                    color: colors.tertiaryText,
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 36),
                  suffixText: 'RWF',
                  suffixStyle: theme.textTheme.labelSmall?.copyWith(
                    color: colors.tertiaryText,
                    fontWeight: FontWeight.w700,
                  ),
                  filled: true,
                  fillColor: colors.chipBackground,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(CoolRadii.sm),
                    borderSide: BorderSide.none,
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: CoolSpace.x3),
              TextField(
                controller: _allocationNoteController,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.primaryText,
                ),
                decoration: InputDecoration(
                  hintText: context.l10n.adminSavingsHintNote,
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.tertiaryText,
                  ),
                  prefixIcon: Icon(
                    CoolIcons.stickyNote,
                    size: 18,
                    color: colors.tertiaryText,
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 36),
                  filled: true,
                  fillColor: colors.chipBackground,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(CoolRadii.sm),
                    borderSide: BorderSide.none,
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: CoolSpace.x5),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isAllocating || _selectedMemberUserId == null
                      ? null
                      : () => _handleAllocateContribution(groupId),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(CoolRadii.sm),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    _isAllocating
                        ? context.l10n.adminSavingsAllocating
                        : context.l10n.adminSavingsAllocate,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
