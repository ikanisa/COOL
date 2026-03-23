import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/status/models/cool_mission.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../providers/admin_gamification_providers.dart';
import '../repositories/admin_gamification_repository.dart';
import '../widgets/live_ops_admin_widgets.dart';

EdgeInsets _liveOpsHeaderPadding() =>
    CoolSpace.pagePadding.copyWith(top: 0, bottom: 0);

EdgeInsets _liveOpsLoadingPadding() => CoolSpace.scaffoldPadding;

EdgeInsets _liveOpsListPadding() => CoolSpace.scaffoldPadding;

EdgeInsets _liveOpsSheetHeaderPadding() =>
    CoolSpace.pagePadding.copyWith(top: 0, bottom: 0);

EdgeInsets _liveOpsSheetListPadding() =>
    CoolSpace.pagePadding.copyWith(top: 0, bottom: CoolSpace.x7);

/// Admin CRUD screen for managing cooperative missions.
class ManageMissionsScreen extends ConsumerWidget {
  const ManageMissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final missionsAsync = ref.watch(adminMissionsProvider);

    return CoolScreenBackground(
      showGlow: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            tooltip: context.l10n.back,
            icon: Icon(Icons.arrow_back_rounded, color: colors.primaryText),
          ),
        ),
        floatingActionButton: Semantics(
          button: true,
          label: 'Create mission',
          hint: 'Open mission form',
          child: FloatingActionButton(
            backgroundColor: colors.accent,
            foregroundColor: colors.accentForeground,
            onPressed: () => _showEditSheet(context, ref, null),
            child: const Icon(Icons.add_rounded),
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: _liveOpsHeaderPadding(),
              child: Semantics(
                header: true,
                child: Text(
                  'Missions',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: _liveOpsHeaderPadding(),
              child: Text(
                'Manage cooperative goals and reward rules',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.secondaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: CoolAsyncView<List<CoolMission>>(
                value: missionsAsync,
                onRetry: () => ref.invalidate(adminMissionsProvider),
                loadingWidget: Padding(
                  padding: _liveOpsLoadingPadding(),
                  child: const CoolSkeletonList(itemCount: 4),
                ),
                emptyCheck: (missions) => missions.isEmpty,
                emptyWidget: CoolEmptyView(
                  message: 'No missions yet',
                  icon: Icons.flag_outlined,
                  actionLabel: 'Create Mission',
                  onAction: () => _showEditSheet(context, ref, null),
                ),
                builder: (missions) {
                  final activeCount = missions.where((m) => m.isActive).length;
                  final liveCount = missions.where((m) => m.isLive).length;
                  final rewardPool = missions.fold<int>(
                    0,
                    (sum, mission) => sum + mission.rewardPoints,
                  );

                  return ListView.separated(
                    padding: _liveOpsListPadding(),
                    itemCount: missions.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _MissionSummaryCard(
                          totalCount: missions.length,
                          activeCount: activeCount,
                          liveCount: liveCount,
                          rewardPool: rewardPool,
                        );
                      }

                      final mission = missions[index - 1];
                      return _MissionAdminCard(
                        mission: mission,
                        onEdit: () => _showEditSheet(context, ref, mission),
                        onToggle: () => _toggleActive(context, ref, mission),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditSheet(
    BuildContext context,
    WidgetRef ref,
    CoolMission? mission,
  ) {
    showCoolBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _MissionEditSheet(
        mission: mission,
        repo: ref.read(adminGamificationRepositoryProvider),
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
      final repo = ref.read(adminGamificationRepositoryProvider);
      await repo.toggleMissionActive(mission.id, isActive: !mission.isActive);
      ref.invalidate(adminMissionsProvider);
      if (context.mounted) {
        CoolToast.success(
          context,
          mission.isActive
              ? '${mission.title} deactivated'
              : '${mission.title} activated',
        );
      }
    } catch (e) {
      if (context.mounted) {
        CoolToast.error(context, 'Failed: $e');
      }
    }
  }
}

class _MissionSummaryCard extends StatelessWidget {
  const _MissionSummaryCard({
    required this.totalCount,
    required this.activeCount,
    required this.liveCount,
    required this.rewardPool,
  });

  final int totalCount;
  final int activeCount;
  final int liveCount;
  final int rewardPool;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return CoolCard(
      backgroundColor: colors.analyticsSurface,
      useGradient: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current Mission Mix',
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Keep live goals active and reward pressure visible',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: LiveOpsMetricPill(
                  label: 'Total',
                  value: '$totalCount',
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: LiveOpsMetricPill(
                  label: 'Live',
                  value: '$liveCount',
                  color: colors.success,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: LiveOpsMetricPill(
                  label: 'Reward Pool',
                  value: '$rewardPool',
                  color: colors.warning,
                ),
              ),
            ],
          ),
          if (activeCount != liveCount) ...[
            const SizedBox(height: 10),
            Text(
              '$activeCount active missions configured',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.tertiaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final dateFmt = DateFormat('dd MMM yyyy');
    final status = _missionStatus(context, mission);

    return CoolCard(
      onTap: onEdit,
      backgroundColor: colors.operationalSurface,
      useGradient: false,
      semanticsLabel: 'Edit ${mission.title}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.teamSurface,
              borderRadius: const BorderRadius.all(
                Radius.circular(CoolRadii.xs),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              mission.emoji,
              style: theme.textTheme.titleLarge?.copyWith(height: 1),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        mission.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colors.primaryText,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    LiveOpsStatusBadge(
                      label: status.label,
                      color: status.color,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${mission.missionType.displayLabel} · ${mission.scope.name} · ${dateFmt.format(mission.startsAt)} – ${dateFmt.format(mission.endsAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.tertiaryText,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Target ${mission.targetValue} · Reward ${mission.rewardPoints} tokens',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.secondaryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onToggle,
            tooltip: mission.isActive
                ? 'Deactivate mission'
                : 'Activate mission',
            icon: Icon(
              mission.isActive
                  ? Icons.toggle_on_rounded
                  : Icons.toggle_off_rounded,
              size: 32,
              color: mission.isActive ? colors.success : colors.tertiaryText,
            ),
          ),
        ],
      ),
    );
  }

  _LifecycleState _missionStatus(BuildContext context, CoolMission mission) {
    final colors = context.coolSemanticColors;
    if (!mission.isActive) {
      return _LifecycleState('Inactive', colors.danger);
    }
    if (mission.isExpired) {
      return _LifecycleState('Ended', colors.neutral);
    }
    if (mission.isUpcoming) {
      return _LifecycleState('Upcoming', colors.warning);
    }
    return _LifecycleState('Live', colors.success);
  }
}

class _MissionEditSheet extends StatefulWidget {
  const _MissionEditSheet({
    this.mission,
    required this.repo,
    required this.onSaved,
  });

  final CoolMission? mission;
  final AdminGamificationRepository repo;
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

  static const List<String> _missionTypes = <String>[
    'savings_sprint',
    'supporter_season',
    'commuter_week',
    'matchday_month',
  ];

  static const List<String> _scopeTypes = <String>[
    'global',
    'group',
    'chapter',
  ];

  @override
  void initState() {
    super.initState();
    final mission = widget.mission;
    _titleCtrl = TextEditingController(text: mission?.title ?? '');
    _descCtrl = TextEditingController(text: mission?.description ?? '');
    _emojiCtrl = TextEditingController(text: mission?.emoji ?? '🎯');
    _targetCtrl = TextEditingController(
      text: mission != null ? '${mission.targetValue}' : '',
    );
    _rewardPtsCtrl = TextEditingController(
      text: mission != null ? '${mission.rewardPoints}' : '0',
    );
    _rewardDescCtrl = TextEditingController(
      text: mission?.rewardDescription ?? '',
    );
    _scopeIdCtrl = TextEditingController(text: mission?.scopeId ?? '');
    _missionType = mission?.missionType.value ?? _missionTypes.first;
    if (!_missionTypes.contains(_missionType)) {
      _missionType = _missionTypes.first;
    }
    _scopeType = mission?.scope.value ?? 'global';
    if (!_scopeTypes.contains(_scopeType)) {
      _scopeType = 'global';
    }
    _startsAt = mission?.startsAt ?? DateTime.now();
    _endsAt = mission?.endsAt ?? DateTime.now().add(const Duration(days: 14));
    _isActive = mission?.isActive ?? true;
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
    if (picked == null) {
      return;
    }
    setState(() {
      if (isStart) {
        _startsAt = picked;
      } else {
        _endsAt = picked;
      }
    });
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
        'description': _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        'emoji': _emojiCtrl.text.trim().isEmpty ? '🎯' : _emojiCtrl.text.trim(),
        'mission_type': _missionType,
        'target_value': int.tryParse(_targetCtrl.text.trim()) ?? 0,
        'scope_type': _scopeType,
        'scope_id': _scopeIdCtrl.text.trim().isEmpty
            ? null
            : _scopeIdCtrl.text.trim(),
        'starts_at': _startsAt.toIso8601String(),
        'ends_at': _endsAt.toIso8601String(),
        'reward_points': int.tryParse(_rewardPtsCtrl.text.trim()) ?? 0,
        'reward_description': _rewardDescCtrl.text.trim().isEmpty
            ? null
            : _rewardDescCtrl.text.trim(),
        'is_active': _isActive,
      };

      await widget.repo.upsertMission(data);
      widget.onSaved();
      if (mounted) {
        Navigator.of(context).pop();
        CoolToast.success(
          context,
          _isNew ? 'Mission created' : 'Mission updated',
        );
      }
    } catch (e) {
      if (mounted) {
        CoolToast.error(context, 'Save failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final dateFmt = DateFormat('dd MMM yyyy');

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      decoration: BoxDecoration(
        color: colors.overlaySurface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(CoolRadii.lg),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colors.border,
              borderRadius: const BorderRadius.all(
                Radius.circular(CoolRadii.pill),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: _liveOpsSheetHeaderPadding(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isNew ? 'Create Mission' : 'Edit Mission',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: colors.primaryText,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Set the goal, timing, and reward',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.secondaryText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      context.l10n.active,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.tertiaryText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Switch.adaptive(
                      value: _isActive,
                      activeTrackColor: colors.success,
                      onChanged: (value) => setState(() => _isActive = value),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView(
              padding: _liveOpsSheetListPadding(),
              shrinkWrap: true,
              children: [
                LiveOpsTextField(label: 'Title', controller: _titleCtrl),
                LiveOpsTextField(
                  label: 'Description',
                  controller: _descCtrl,
                  maxLines: 2,
                ),
                LiveOpsTextField(label: 'Emoji', controller: _emojiCtrl),
                LiveOpsDropdownField(
                  label: 'Mission Type',
                  value: _missionType,
                  items: _missionTypes,
                  onChanged: (value) => setState(() => _missionType = value),
                ),
                LiveOpsTextField(
                  label: 'Target Value',
                  controller: _targetCtrl,
                  keyboardType: TextInputType.number,
                ),
                LiveOpsDropdownField(
                  label: 'Scope',
                  value: _scopeType,
                  items: _scopeTypes,
                  onChanged: (value) => setState(() => _scopeType = value),
                ),
                LiveOpsTextField(label: 'Scope ID', controller: _scopeIdCtrl),
                Row(
                  children: [
                    Expanded(
                      child: LiveOpsDateButton(
                        label: 'Starts',
                        value: dateFmt.format(_startsAt),
                        onTap: () => _pickDate(true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: LiveOpsDateButton(
                        label: 'Ends',
                        value: dateFmt.format(_endsAt),
                        onTap: () => _pickDate(false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LiveOpsTextField(
                  label: 'Reward Tokens',
                  controller: _rewardPtsCtrl,
                  keyboardType: TextInputType.number,
                ),
                LiveOpsTextField(
                  label: 'Reward Description',
                  controller: _rewardDescCtrl,
                ),
                const SizedBox(height: 16),
                CoolButton(
                  label: _isNew ? 'Create Mission' : 'Save Mission',
                  onTap: _save,
                  isLoading: _saving,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LifecycleState {
  const _LifecycleState(this.label, this.color);

  final String label;
  final Color color;
}
