import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/status/models/cool_season.dart';
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

/// Admin CRUD screen for managing seasons (live-ops campaigns).
class ManageSeasonsScreen extends ConsumerWidget {
  const ManageSeasonsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final seasonsAsync = ref.watch(adminSeasonsProvider);

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
          label: 'Create season',
          hint: 'Open season form',
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
                  'Seasons',
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
                'Schedule live campaigns and reward windows',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.secondaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: CoolSpace.x4),
            Expanded(
              child: CoolAsyncView<List<CoolSeason>>(
                value: seasonsAsync,
                onRetry: () => ref.invalidate(adminSeasonsProvider),
                loadingWidget: Padding(
                  padding: _liveOpsLoadingPadding(),
                  child: const CoolSkeletonList(itemCount: 4),
                ),
                emptyCheck: (seasons) => seasons.isEmpty,
                emptyWidget: CoolEmptyView(
                  message: 'No seasons yet',
                  icon: Icons.event_available_outlined,
                  actionLabel: 'Create Season',
                  onAction: () => _showEditSheet(context, ref, null),
                ),
                builder: (seasons) {
                  final liveCount = seasons.where((s) => s.isLive).length;
                  final upcomingCount = seasons
                      .where((s) => s.isUpcoming)
                      .length;
                  final activeCount = seasons.where((s) => s.isActive).length;

                  return ListView.separated(
                    padding: _liveOpsListPadding(),
                    itemCount: seasons.length + 1,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: CoolSpace.x3),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _SeasonSummaryCard(
                          totalCount: seasons.length,
                          liveCount: liveCount,
                          upcomingCount: upcomingCount,
                          activeCount: activeCount,
                        );
                      }

                      final season = seasons[index - 1];
                      return _SeasonAdminCard(
                        season: season,
                        onEdit: () => _showEditSheet(context, ref, season),
                        onToggle: () => _toggleActive(context, ref, season),
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
          season.isActive
              ? '${season.title} deactivated'
              : '${season.title} activated',
        );
      }
    } catch (e) {
      if (context.mounted) {
        CoolToast.error(context, 'Failed: $e');
      }
    }
  }
}

class _SeasonSummaryCard extends StatelessWidget {
  const _SeasonSummaryCard({
    required this.totalCount,
    required this.liveCount,
    required this.upcomingCount,
    required this.activeCount,
  });

  final int totalCount;
  final int liveCount;
  final int upcomingCount;
  final int activeCount;

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
            'Campaign Window',
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Track what is live now and what launches next',
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
                  label: 'Upcoming',
                  value: '$upcomingCount',
                  color: colors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '$activeCount active campaigns configured',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.tertiaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final dateFmt = DateFormat('dd MMM yyyy');
    final status = _seasonStatus(context, season);

    return CoolCard(
      onTap: onEdit,
      backgroundColor: colors.operationalSurface,
      useGradient: false,
      semanticsLabel: 'Edit ${season.title}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.analyticsSurface,
              borderRadius: const BorderRadius.all(
                Radius.circular(CoolRadii.xs),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              season.emoji,
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
                        season.title,
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
                  '${_themeLabel(season.theme)} · ${dateFmt.format(season.startsAt)} – ${dateFmt.format(season.endsAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.tertiaryText,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if ((season.rewardsDescription ?? '').isNotEmpty) ...[
                  const SizedBox(height: CoolSpace.x1),
                  Text(
                    season.rewardsDescription!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.secondaryText,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onToggle,
            tooltip: season.isActive ? 'Deactivate season' : 'Activate season',
            icon: Icon(
              season.isActive
                  ? Icons.toggle_on_rounded
                  : Icons.toggle_off_rounded,
              size: 32,
              color: season.isActive ? colors.success : colors.tertiaryText,
            ),
          ),
        ],
      ),
    );
  }

  _LifecycleState _seasonStatus(BuildContext context, CoolSeason season) {
    final colors = context.coolSemanticColors;
    if (!season.isActive) {
      return _LifecycleState('Inactive', colors.danger);
    }
    if (season.isExpired) {
      return _LifecycleState('Ended', colors.neutral);
    }
    if (season.isUpcoming) {
      return _LifecycleState('Upcoming', colors.warning);
    }
    return _LifecycleState('Live', colors.success);
  }

  String _themeLabel(String theme) {
    final parts = theme.split('_').where((part) => part.isNotEmpty);
    return parts
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}

class _SeasonEditSheet extends StatefulWidget {
  const _SeasonEditSheet({
    this.season,
    required this.repo,
    required this.onSaved,
  });

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

  static const List<String> _themes = <String>[
    'savings',
    'supporter',
    'commuter',
    'matchday',
  ];

  @override
  void initState() {
    super.initState();
    final season = widget.season;
    _titleCtrl = TextEditingController(text: season?.title ?? '');
    _emojiCtrl = TextEditingController(text: season?.emoji ?? '🏅');
    _rewardsCtrl = TextEditingController(
      text: season?.rewardsDescription ?? '',
    );
    _theme = season?.theme ?? _themes.first;
    if (!_themes.contains(_theme)) {
      _theme = _themes.first;
    }
    _startsAt = season?.startsAt ?? DateTime.now();
    _endsAt = season?.endsAt ?? DateTime.now().add(const Duration(days: 28));
    _isActive = season?.isActive ?? false;
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
        'rewards_description': _rewardsCtrl.text.trim().isEmpty
            ? null
            : _rewardsCtrl.text.trim(),
      };

      await widget.repo.upsertSeason(data);
      widget.onSaved();
      if (mounted) {
        Navigator.of(context).pop();
        CoolToast.success(
          context,
          _isNew ? 'Season created' : 'Season updated',
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
        maxHeight: MediaQuery.of(context).size.height * 0.9,
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
          const SizedBox(height: CoolSpace.x3),
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
          const SizedBox(height: CoolSpace.x4),
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
                        _isNew ? 'Create Season' : 'Edit Season',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: colors.primaryText,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: CoolSpace.x1),
                      Text(
                        'Set the campaign window and reward pitch',
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
          const SizedBox(height: CoolSpace.x3),
          Flexible(
            child: ListView(
              padding: _liveOpsSheetListPadding(),
              shrinkWrap: true,
              children: [
                LiveOpsTextField(label: 'Title', controller: _titleCtrl),
                LiveOpsTextField(label: 'Emoji', controller: _emojiCtrl),
                LiveOpsDropdownField(
                  label: 'Theme',
                  value: _theme,
                  items: _themes,
                  onChanged: (value) => setState(() => _theme = value),
                ),
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
                const SizedBox(height: CoolSpace.x3),
                LiveOpsTextField(
                  label: 'Rewards Description',
                  controller: _rewardsCtrl,
                  maxLines: 2,
                ),
                const SizedBox(height: CoolSpace.x4),
                CoolButton(
                  label: _isNew ? 'Create Season' : 'Save Season',
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
