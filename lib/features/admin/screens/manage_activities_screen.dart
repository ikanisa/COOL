import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/status/models/cool_activity.dart';
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

/// Admin CRUD screen for managing token-earning activities.
class ManageActivitiesScreen extends ConsumerWidget {
  const ManageActivitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final activitiesAsync = ref.watch(adminActivitiesProvider);

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
          label: 'Create activity',
          hint: 'Open activity form',
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
                  'Activities',
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
                'Define token actions and sort order',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.secondaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: CoolSpace.x4),
            Expanded(
              child: CoolAsyncView<List<CoolActivity>>(
                value: activitiesAsync,
                onRetry: () => ref.invalidate(adminActivitiesProvider),
                loadingWidget: Padding(
                  padding: _liveOpsLoadingPadding(),
                  child: const CoolSkeletonList(itemCount: 4),
                ),
                emptyCheck: (activities) => activities.isEmpty,
                emptyWidget: CoolEmptyView(
                  message: 'No activities yet',
                  icon: Icons.bolt_outlined,
                  actionLabel: 'Create Activity',
                  onAction: () => _showEditSheet(context, ref, null),
                ),
                builder: (activities) {
                  final activeCount = activities
                      .where((activity) => activity.isActive)
                      .length;
                  final totalTokens = activities.fold<int>(
                    0,
                    (sum, activity) => sum + activity.tokensAwarded,
                  );
                  final categories = activities
                      .map((activity) => activity.category)
                      .toSet()
                      .length;

                  return ListView.separated(
                    padding: _liveOpsListPadding(),
                    itemCount: activities.length + 1,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: CoolSpace.x3),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _ActivitySummaryCard(
                          totalCount: activities.length,
                          activeCount: activeCount,
                          totalTokens: totalTokens,
                          categoryCount: categories,
                        );
                      }

                      final activity = activities[index - 1];
                      return _ActivityAdminCard(
                        activity: activity,
                        onEdit: () => _showEditSheet(context, ref, activity),
                        onToggle: () => _toggleActive(context, ref, activity),
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
    CoolActivity? activity,
  ) {
    showCoolBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ActivityEditSheet(
        activity: activity,
        repo: ref.read(adminGamificationRepositoryProvider),
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
      final repo = ref.read(adminGamificationRepositoryProvider);
      await repo.toggleActivityActive(
        activity.id,
        isActive: !activity.isActive,
      );
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
      if (context.mounted) {
        CoolToast.error(context, 'Failed: $e');
      }
    }
  }
}

class _ActivitySummaryCard extends StatelessWidget {
  const _ActivitySummaryCard({
    required this.totalCount,
    required this.activeCount,
    required this.totalTokens,
    required this.categoryCount,
  });

  final int totalCount;
  final int activeCount;
  final int totalTokens;
  final int categoryCount;

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
            'Activity Coverage',
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Keep earning actions clear and reward values balanced',
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
                  label: 'Active',
                  value: '$activeCount',
                  color: colors.success,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: LiveOpsMetricPill(
                  label: 'Categories',
                  value: '$categoryCount',
                  color: colors.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '$totalTokens total tokens across the current catalog',
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return CoolCard(
      onTap: onEdit,
      backgroundColor: colors.operationalSurface,
      useGradient: false,
      semanticsLabel: 'Edit ${activity.title}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.contactSurface,
              borderRadius: const BorderRadius.all(
                Radius.circular(CoolRadii.xs),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              activity.emoji,
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
                        activity.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colors.primaryText,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    LiveOpsStatusBadge(
                      label: activity.isActive ? 'Active' : 'Inactive',
                      color: activity.isActive ? colors.success : colors.danger,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${_categoryLabel(activity.category)} · ${activity.tokensAwarded} tokens · sort ${activity.sortOrder}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.tertiaryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (activity.description.isNotEmpty) ...[
                  const SizedBox(height: CoolSpace.x1),
                  Text(
                    activity.description,
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
            tooltip: activity.isActive
                ? 'Deactivate activity'
                : 'Activate activity',
            icon: Icon(
              activity.isActive
                  ? Icons.toggle_on_rounded
                  : Icons.toggle_off_rounded,
              size: 32,
              color: activity.isActive ? colors.success : colors.tertiaryText,
            ),
          ),
        ],
      ),
    );
  }

  String _categoryLabel(String category) {
    final parts = category.split('_').where((part) => part.isNotEmpty);
    return parts
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}

class _ActivityEditSheet extends StatefulWidget {
  const _ActivityEditSheet({
    this.activity,
    required this.repo,
    required this.onSaved,
  });

  final CoolActivity? activity;
  final AdminGamificationRepository repo;
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

  static const List<String> _categories = <String>[
    'groups',
    'rayon',
    'social',
    'general',
  ];

  @override
  void initState() {
    super.initState();
    final activity = widget.activity;
    _titleCtrl = TextEditingController(text: activity?.title ?? '');
    _descCtrl = TextEditingController(text: activity?.description ?? '');
    _emojiCtrl = TextEditingController(text: activity?.emoji ?? '⭐');
    _slugCtrl = TextEditingController(text: activity?.slug ?? '');
    _tokensCtrl = TextEditingController(
      text: activity != null ? '${activity.tokensAwarded}' : '20',
    );
    _sortCtrl = TextEditingController(
      text: activity != null ? '${activity.sortOrder}' : '0',
    );
    _category = activity?.category ?? _categories.first;
    if (!_categories.contains(_category)) {
      _category = _categories.first;
    }
    _isActive = activity?.isActive ?? true;
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

      await widget.repo.upsertActivity(data);
      widget.onSaved();
      if (mounted) {
        Navigator.of(context).pop();
        CoolToast.success(
          context,
          _isNew ? 'Activity created' : 'Activity updated',
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
                        _isNew ? 'Create Activity' : 'Edit Activity',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: colors.primaryText,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: CoolSpace.x1),
                      Text(
                        'Define the action, reward, and rank',
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
                LiveOpsTextField(label: 'Slug', controller: _slugCtrl),
                LiveOpsTextField(
                  label: 'Description',
                  controller: _descCtrl,
                  maxLines: 2,
                ),
                LiveOpsTextField(label: 'Emoji', controller: _emojiCtrl),
                LiveOpsDropdownField(
                  label: 'Category',
                  value: _category,
                  items: _categories,
                  onChanged: (value) => setState(() => _category = value),
                ),
                LiveOpsTextField(
                  label: 'Tokens Awarded',
                  controller: _tokensCtrl,
                  keyboardType: TextInputType.number,
                ),
                LiveOpsTextField(
                  label: 'Sort Order',
                  controller: _sortCtrl,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: CoolSpace.x4),
                CoolButton(
                  label: _isNew ? 'Create Activity' : 'Save Activity',
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
