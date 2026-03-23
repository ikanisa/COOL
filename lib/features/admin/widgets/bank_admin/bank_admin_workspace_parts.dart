// ignore_for_file: invalid_use_of_protected_member
part of '../../screens/bank_admin_workspace_screen.dart';

EdgeInsets _bankWorkspaceModalInsets(BuildContext context) {
  final space = context.coolSpace;
  return CoolSpace.denseSectionPadding.copyWith(
    top: space.x5,
    bottom: MediaQuery.of(context).viewInsets.bottom + space.x5,
  );
}

EdgeInsets _bankWorkspaceSuggestionPadding() =>
    CoolSpace.sectionPadding.copyWith(
      left: CoolSpace.x3,
      right: CoolSpace.x3,
      top: CoolSpace.x3,
      bottom: CoolSpace.x3,
    );

EdgeInsets _bankWorkspaceZeroPadding() =>
    CoolSpace.sectionPadding.copyWith(left: 0, right: 0, top: 0, bottom: 0);

const BorderRadius _bankWorkspaceHandleRadius = BorderRadius.all(
  Radius.circular(CoolRadii.pill),
);

const BorderRadius _bankWorkspaceSuggestionRadius = BorderRadius.all(
  Radius.circular(CoolRadii.xs),
);

/// Methods extracted from [_BankAdminWorkspaceScreenState] for readability.
/// This file is a `part of` the parent library, so these are instance members.
extension _BankAdminWorkspaceScreenStateParts
    on _BankAdminWorkspaceScreenState {
  void _syncSelectedGroup(List<BankAdminGroupSummary> groups) {
    final hasSelection =
        _selectedGroupId != null &&
        groups.any((group) => group.id == _selectedGroupId);
    final nextSelection = groups.isEmpty ? null : groups.first.id;

    if (hasSelection || nextSelection == _selectedGroupId) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() => _selectedGroupId = nextSelection);
    });
  }

  BankAdminGroupSummary? _selectedGroup(List<BankAdminGroupSummary> groups) {
    for (final group in groups) {
      if (group.id == _selectedGroupId) {
        return group;
      }
    }
    return groups.isEmpty ? null : groups.first;
  }

  void _openLedgerTab(String groupId) {
    setState(() => _selectedGroupId = groupId);
    _tabController.animateTo(3);
  }

  void _openGroupDetail(
    BankAdminGroupSummary group,
    BankAdminWorkspaceSnapshot snapshot,
  ) {
    showCoolBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.coolSemanticColors.overlaySurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(CoolRadii.lg)),
      ),
      builder: (context) => BankGroupDetailSheet(
        group: group,
        members: snapshot.members.entries
            .where((member) => member.groupId == group.id)
            .toList(growable: false),
        contributions: snapshot.contributions.entries
            .where((contribution) => contribution.groupId == group.id)
            .toList(growable: false),
        onOpenLedger: group.id.isEmpty
            ? null
            : () {
                Navigator.of(context).pop();
                _openLedgerTab(group.id);
              },
      ),
    );
  }

  Future<void> _exportLedger({
    required StatementExportFormat format,
    required String partnerName,
    required BankAdminGroupSummary group,
    required List<PayeePaymentLedgerEntry> entries,
  }) async {
    if (_isExportingLedger || entries.isEmpty) {
      return;
    }

    setState(() => _isExportingLedger = true);
    try {
      final authState = ref.read(authProvider);
      final exportService = ref.read(momoStatementExportServiceProvider);
      final downloadService = ref.read(momoStatementDownloadServiceProvider);
      final export = await exportService.buildPayeeLedgerExport(
        format: format,
        entries: entries,
        metadata: StatementExportMetadata(
          statementTitle: '${group.group.name} payment ledger',
          fileStem:
              'bank_${bankFileSafe(partnerName)}_${bankFileSafe(group.group.name)}_ledger',
          userName: authState.user?.fullName.trim().isNotEmpty == true
              ? authState.user!.fullName.trim()
              : partnerName,
          officialPhone:
              authState.user?.officialPhone ??
              authState.user?.phone ??
              group.group.momoNumber ??
              '',
          generatedAt: DateTime.now(),
          periodLabel: 'All posted entries in view',
          filterLabel: 'Group payment ledger',
          sortLabel: 'Newest first',
        ),
      );
      final result = await downloadService.saveExport(export);
      if (!mounted) {
        return;
      }
      CoolToast.success(context, 'Ledger exported to ${result.fileName}.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      CoolToast.error(context, 'Could not export this ledger right now.');
    } finally {
      if (mounted) {
        setState(() => _isExportingLedger = false);
      }
    }
  }

  Future<void> _allocateManualReview({
    required BankAdminAllocationReviewItem item,
    required String groupId,
    required String memberUserId,
  }) async {
    if (_activeReviewId != null) {
      return;
    }

    setState(() {
      _activeReviewId = item.reviewId;
      _activeReviewAction = 'allocate';
    });

    try {
      final repository = ref.read(bankAdminRepositoryProvider);
      await repository.allocateManualReviewToGroupContribution(
        partnerId: widget.partnerId,
        reviewId: item.reviewId,
        groupId: groupId,
        memberUserId: memberUserId,
      );
      ref.invalidate(bankAdminWorkspaceProvider(widget.partnerId));
      ref.invalidate(
        groupPaymentLedgerProvider(
          GroupPaymentLedgerQuery(
            groupId: groupId,
            statementQuery: const MomoStatementQuery(limit: 100),
          ),
        ),
      );
      if (mounted) {
        setState(() => _selectedGroupId = groupId);
        CoolToast.success(
          context,
          'Payment allocated to the selected group member.',
        );
      }
    } catch (_) {
      if (mounted) {
        CoolToast.error(context, 'Could not allocate this payment right now.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _activeReviewId = null;
          _activeReviewAction = null;
        });
      }
    }
  }

  Future<void> _rejectManualReview(BankAdminAllocationReviewItem item) async {
    if (_activeReviewId != null) {
      return;
    }

    final shouldReject = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.rejectAllocation),
        content: const Text('This will remove the'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.reject),
          ),
        ],
      ),
    );

    if (shouldReject != true || !mounted) {
      return;
    }

    setState(() {
      _activeReviewId = item.reviewId;
      _activeReviewAction = 'reject';
    });

    try {
      final repository = ref.read(bankAdminRepositoryProvider);
      await repository.rejectManualReviewAllocation(
        partnerId: widget.partnerId,
        reviewId: item.reviewId,
      );
      ref.invalidate(bankAdminWorkspaceProvider(widget.partnerId));
      if (mounted) {
        CoolToast.success(context, 'Payment marked as rejected.');
      }
    } catch (_) {
      if (mounted) {
        CoolToast.error(context, 'Could not reject this payment right now.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _activeReviewId = null;
          _activeReviewAction = null;
        });
      }
    }
  }

  Future<void> _acceptSuggestion(BankAdminAllocationReviewItem item) async {
    if (_activeReviewId != null) return;
    setState(() {
      _activeReviewId = item.reviewId;
      _activeReviewAction = 'accept';
    });
    try {
      final repository = ref.read(bankAdminRepositoryProvider);
      await repository.acceptSuggestedAllocation(
        partnerId: widget.partnerId,
        reviewId: item.reviewId,
      );
      ref.invalidate(bankAdminWorkspaceProvider(widget.partnerId));
      if (mounted) {
        CoolToast.success(
          context,
          'AI suggestion accepted — payment allocated.',
        );
      }
    } catch (_) {
      if (mounted) {
        CoolToast.error(context, 'Could not accept suggestion.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _activeReviewId = null;
          _activeReviewAction = null;
        });
      }
    }
  }

  Future<void> _triggerAiAllocation() async {
    if (_isAiRunning) return;
    setState(() => _isAiRunning = true);
    try {
      final repository = ref.read(bankAdminRepositoryProvider);
      await repository.triggerAiAllocation(widget.partnerId);
      ref.invalidate(bankAdminWorkspaceProvider(widget.partnerId));
      if (mounted) {
        CoolToast.success(
          context,
          'AI allocation complete — check suggestions.',
        );
      }
    } catch (_) {
      if (mounted) {
        CoolToast.error(context, 'AI allocation failed.');
      }
    } finally {
      if (mounted) {
        setState(() => _isAiRunning = false);
      }
    }
  }

  Future<void> _showAllocationSheet(
    BankAdminAllocationReviewItem item,
    BankAdminWorkspaceSnapshot snapshot,
  ) async {
    if (_activeReviewId != null || snapshot.groups.entries.isEmpty) {
      return;
    }

    final groups = snapshot.groups.entries;
    String selectedGroupId =
        groups.any((group) => group.id == item.groupId && group.id.isNotEmpty)
        ? item.groupId
        : groups.first.id;

    // If AI suggestion exists, prefer suggested group
    if (item.isSuggested && item.suggestedGroupId != null) {
      final suggestedExists = groups.any((g) => g.id == item.suggestedGroupId);
      if (suggestedExists) {
        selectedGroupId = item.suggestedGroupId!;
      }
    }

    List<BankAdminMemberRecord> membersFor(String groupId) {
      return snapshot.members.entries
          .where((member) => member.groupId == groupId)
          .toList(growable: false);
    }

    String? initialMemberId() {
      final scopedMembers = membersFor(selectedGroupId);
      if (scopedMembers.isEmpty) return null;
      // Prefer AI suggestion
      if (item.isSuggested && item.suggestedMemberUserId != null) {
        final match = scopedMembers.where(
          (m) => m.userId == item.suggestedMemberUserId,
        );
        if (match.isNotEmpty) return match.first.userId;
      }
      final matchedMember = scopedMembers.where(
        (member) => member.userId == item.payerUserId,
      );
      if (matchedMember.isNotEmpty) return matchedMember.first.userId;
      return scopedMembers.first.userId;
    }

    String? selectedMemberId = initialMemberId();
    String memberSearchQuery = '';
    bool showCreateMember = false;
    final phoneCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    bool isCreatingMember = false;

    await showCoolBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.coolSemanticColors.overlaySurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final colors = context.coolSemanticColors;
          final theme = Theme.of(context);
          var scopedMembers = membersFor(selectedGroupId);
          // Apply search filter
          if (memberSearchQuery.isNotEmpty) {
            final q = memberSearchQuery.toLowerCase();
            scopedMembers = scopedMembers
                .where((m) => m.displayName.toLowerCase().contains(q))
                .toList(growable: false);
          }
          if (selectedMemberId != null &&
              scopedMembers.every(
                (member) => member.userId != selectedMemberId,
              )) {
            selectedMemberId = scopedMembers.isEmpty
                ? null
                : scopedMembers.first.userId;
          }

          return SafeArea(
            top: false,
            child: Padding(
              padding: _bankWorkspaceModalInsets(context),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.border,
                          borderRadius: _bankWorkspaceHandleRadius,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Allocate payment',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colors.primaryText,
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x2),
                    Text(
                      '${NumberFormat.decimalPattern('en_US').format(item.amount)} RWF · ${item.groupName}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.secondaryText,
                      ),
                    ),
                    // ── AI suggestion banner ──
                    if (item.isSuggested) ...[
                      const SizedBox(height: CoolSpace.x3),
                      Container(
                        padding: _bankWorkspaceSuggestionPadding(),
                        decoration: BoxDecoration(
                          color: colors.accent.withValues(alpha: 0.08),
                          borderRadius: _bankWorkspaceSuggestionRadius,
                          border: Border.all(
                            color: colors.accent.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.auto_awesome,
                                  size: 16,
                                  color: colors.accent,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'AI Suggestion · ${(item.suggestedConfidence ?? 0).toStringAsFixed(0)}% match',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: colors.accent,
                                  ),
                                ),
                              ],
                            ),
                            if (item.suggestedMemberName != null) ...[
                              const SizedBox(height: CoolSpace.x1),
                              Text(
                                'Suggested member: ${item.suggestedMemberName}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.secondaryText,
                                ),
                              ),
                            ],
                            if (item.aiReasoning != null) ...[
                              const SizedBox(height: CoolSpace.x1),
                              Text(
                                item.aiReasoning!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.tertiaryText,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: CoolSpace.x4),
                    // ── Group selector ──
                    DropdownButtonFormField<String>(
                      initialValue: selectedGroupId,
                      decoration: const InputDecoration(labelText: 'Group'),
                      items: groups
                          .map(
                            (group) => DropdownMenuItem<String>(
                              value: group.id,
                              child: Text(group.group.name),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) return;
                        setModalState(() {
                          selectedGroupId = value;
                          memberSearchQuery = '';
                          final nextMembers = membersFor(value);
                          selectedMemberId = nextMembers.isEmpty
                              ? null
                              : nextMembers.first.userId;
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    // ── Member search ──
                    TextField(
                      decoration: InputDecoration(
                        labelText: 'Search member',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: memberSearchQuery.isNotEmpty
                            ? IconButton(
                                tooltip: 'Clear',
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () => setModalState(() {
                                  memberSearchQuery = '';
                                }),
                              )
                            : null,
                      ),
                      onChanged: (v) =>
                          setModalState(() => memberSearchQuery = v),
                    ),
                    const SizedBox(height: CoolSpace.x2),
                    // ── Member dropdown ──
                    if (scopedMembers.isNotEmpty)
                      DropdownButtonFormField<String>(
                        initialValue: selectedMemberId,
                        decoration: const InputDecoration(labelText: 'Member'),
                        items: scopedMembers
                            .map(
                              (member) => DropdownMenuItem<String>(
                                value: member.userId,
                                child: Text(member.displayName),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) =>
                            setModalState(() => selectedMemberId = value),
                      ),
                    if (scopedMembers.isEmpty && !showCreateMember) ...[
                      const SizedBox(height: 10),
                      Text(
                        memberSearchQuery.isNotEmpty
                            ? 'No members match "$memberSearchQuery"'
                            : 'No members in this group',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.warning,
                        ),
                      ),
                    ],
                    const SizedBox(height: CoolSpace.x3),
                    // ── Create new member toggle ──
                    TextButton.icon(
                      onPressed: () => setModalState(
                        () => showCreateMember = !showCreateMember,
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.accent,
                        minimumSize: const Size(0, CoolTapTargets.minimum),
                        padding: _bankWorkspaceZeroPadding(),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: Icon(
                        showCreateMember
                            ? Icons.remove_circle_outline
                            : Icons.add_circle_outline,
                        size: 18,
                      ),
                      label: Text(
                        showCreateMember
                            ? 'Cancel new member'
                            : 'Create new member',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    // ── Create member form ──
                    if (showCreateMember) ...[
                      const SizedBox(height: CoolSpace.x3),
                      TextField(
                        controller: phoneCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Phone number',
                          hintText: '07XXXXXXXX',
                          prefixIcon: Icon(Icons.phone, size: 18),
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Display name (optional)',
                          prefixIcon: Icon(Icons.person, size: 18),
                        ),
                      ),
                      const SizedBox(height: CoolSpace.x3),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed:
                              isCreatingMember || phoneCtrl.text.trim().isEmpty
                              ? null
                              : () async {
                                  setModalState(() => isCreatingMember = true);
                                  try {
                                    final repo = ref.read(
                                      bankAdminRepositoryProvider,
                                    );
                                    final result = await repo.addMemberToGroup(
                                      partnerId: widget.partnerId,
                                      groupId: selectedGroupId,
                                      phone: phoneCtrl.text.trim(),
                                      displayName: nameCtrl.text.trim().isEmpty
                                          ? null
                                          : nameCtrl.text.trim(),
                                    );
                                    final newUserId = result['member_user_id']
                                        ?.toString();
                                    if (newUserId != null &&
                                        newUserId.isNotEmpty) {
                                      ref.invalidate(
                                        bankAdminWorkspaceProvider(
                                          widget.partnerId,
                                        ),
                                      );
                                      if (context.mounted) {
                                        Navigator.of(context).pop();
                                        await _allocateManualReview(
                                          item: item,
                                          groupId: selectedGroupId,
                                          memberUserId: newUserId,
                                        );
                                      }
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      CoolToast.error(
                                        context,
                                        e.toString().replaceAll(
                                          'Exception: ',
                                          '',
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (context.mounted) {
                                      setModalState(
                                        () => isCreatingMember = false,
                                      );
                                    }
                                  }
                                },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colors.accent,
                            side: BorderSide(
                              color: colors.accent.withValues(alpha: 0.65),
                            ),
                            minimumSize: const Size(
                              double.infinity,
                              CoolTapTargets.minimum,
                            ),
                          ),
                          icon: isCreatingMember
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.person_add, size: 18),
                          label: Text(
                            isCreatingMember
                                ? 'Creating...'
                                : 'Add member & allocate',
                          ),
                        ),
                      ),
                    ],
                    if (!showCreateMember) ...[
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: selectedMemberId == null
                              ? null
                              : () async {
                                  Navigator.of(context).pop();
                                  await _allocateManualReview(
                                    item: item,
                                    groupId: selectedGroupId,
                                    memberUserId: selectedMemberId!,
                                  );
                                },
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.accent,
                            foregroundColor: colors.accentForeground,
                            minimumSize: const Size(
                              double.infinity,
                              CoolTapTargets.minimum,
                            ),
                          ),
                          child: Text(context.l10n.allocateToMember),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
