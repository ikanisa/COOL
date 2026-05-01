import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/admin_detail_scaffold.dart';
import '../../../shared/widgets/admin_workspace_kit.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../providers/admin_providers.dart';

/// Audit log viewer — shows all admin actions captured by DB triggers.
class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  String? _selectedAction;

  static const _actionFilters = [
    null, // all
    'create',
    'update',
    'delete',
  ];

  @override
  Widget build(BuildContext context) {
    final logsAsync = ref.watch(adminAuditLogProvider(_selectedAction));

    return AdminDetailScaffold(
      child: CoolAsyncView<List<Map<String, dynamic>>>(
        value: logsAsync,
        onRetry: () => ref.invalidate(adminAuditLogProvider(_selectedAction)),
        loadingWidget: const Padding(
          padding: EdgeInsets.fromLTRB(
            CoolSpace.x5,
            0,
            CoolSpace.x5,
            CoolSpace.x7,
          ),
          child: CoolSkeletonList(itemCount: 6),
        ),
        emptyCheck: (logs) => logs.isEmpty,
        emptyWidget: Padding(
          padding: const EdgeInsets.all(CoolSpace.x5),
          child: CoolEmptyView(
            message: context.l10n.adminAuditEmpty,
            icon: CoolIcons.historyRounded,
          ),
        ),
        builder: (logs) {
          final createCount = logs
              .where((entry) => entry['action'] == 'create')
              .length;
          final updateCount = logs
              .where((entry) => entry['action'] == 'update')
              .length;
          final deleteCount = logs
              .where((entry) => entry['action'] == 'delete')
              .length;

          return ListView(
            padding: CoolSpace.scaffoldPadding,
            children: [
              AdminPageHeader(
                eyebrow: context.l10n.adminAuditEyebrow,
                title: context.l10n.adminAuditTitle,
                subtitle: context.l10n.adminAuditSubtitle,
                badges: [
                  AdminStatusChip(
                    label: context.l10n.adminAuditVisible,
                    trailing: '${logs.length}',
                    tone: AdminTone.accent,
                    icon: CoolIcons.visibility,
                  ),
                ],
              ),
              const SizedBox(height: CoolSpace.x4),
              AdminMetricStrip(
                metrics: [
                  AdminMetricItem(
                    label: context.l10n.adminAuditEntries,
                    value: '${logs.length}',
                    hint: context.l10n.adminAuditCurrentFeed,
                    icon: CoolIcons.receiptOutlined,
                    tone: AdminTone.info,
                  ),
                  AdminMetricItem(
                    label: context.l10n.adminAuditCreate,
                    value: '$createCount',
                    hint: context.l10n.adminAuditNewRecords,
                    icon: CoolIcons.addCircle,
                    tone: AdminTone.success,
                  ),
                  AdminMetricItem(
                    label: context.l10n.adminAuditUpdate,
                    value: '$updateCount',
                    hint: context.l10n.adminAuditChangedRecords,
                    icon: CoolIcons.editOutlined,
                    tone: AdminTone.accent,
                  ),
                  AdminMetricItem(
                    label: context.l10n.adminAuditDelete,
                    value: '$deleteCount',
                    hint: context.l10n.adminAuditRemovedRecords,
                    icon: CoolIcons.delete,
                    tone: AdminTone.danger,
                  ),
                ],
              ),
              const SizedBox(height: CoolSpace.x4),
              AdminToolbar(filters: [_buildActionFilterBar(context)]),
              const SizedBox(height: CoolSpace.x4),
              AdminSectionCard(
                title: context.l10n.adminAuditTimeline,
                subtitle: context.l10n.adminAuditTimelineSubtitle,
                child: Column(
                  children: [
                    for (var index = 0; index < logs.length; index++) ...[
                      _AuditEntryTile(entry: logs[index]),
                      if (index < logs.length - 1)
                        const SizedBox(height: CoolSpace.x2),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActionFilterBar(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return Wrap(
      spacing: CoolSpace.x2,
      runSpacing: CoolSpace.x2,
      children: [
        for (final action in _actionFilters)
          Builder(
            builder: (context) {
              final isSelected = _selectedAction == action;
              final label = action == null
                  ? 'All'
                  : action[0].toUpperCase() + action.substring(1);
              return ChoiceChip(
                showCheckmark: false,
                label: Text(label),
                selected: isSelected,
                onSelected: (_) {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedAction = action);
                },
                backgroundColor: colors.chipBackground,
                selectedColor: colors.chipSelectedBackground,
                labelStyle: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isSelected ? colors.primaryText : colors.secondaryText,
                ),
                side: BorderSide.none,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(
                    Radius.circular(CoolRadii.pill),
                  ),
                ),
                visualDensity: VisualDensity.compact,
              );
            },
          ),
      ],
    );
  }
}

class _AuditEntryTile extends StatefulWidget {
  const _AuditEntryTile({required this.entry});
  final Map<String, dynamic> entry;

  @override
  State<_AuditEntryTile> createState() => _AuditEntryTileState();
}

class _AuditEntryTileState extends State<_AuditEntryTile> {
  bool _expanded = false;

  AdminTone get _tone {
    return switch (widget.entry['action']?.toString()) {
      'create' => AdminTone.success,
      'update' => AdminTone.accent,
      'delete' => AdminTone.danger,
      _ => AdminTone.neutral,
    };
  }

  IconData get _actionIcon {
    return switch (widget.entry['action']?.toString()) {
      'create' => CoolIcons.addCircle,
      'update' => CoolIcons.edit,
      'delete' => CoolIcons.delete,
      _ => CoolIcons.info,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final e = widget.entry;
    final actorName = e['actor_name']?.toString().trim();
    final actorPhone = e['actor_phone']?.toString().trim();
    final displayActor = actorName?.isNotEmpty == true
        ? actorName!
        : actorPhone?.isNotEmpty == true
        ? actorPhone!
        : context.l10n.adminAuditUnknownActor;
    final action = e['action']?.toString() ?? '';
    final targetTable = e['target_table']?.toString() ?? '';
    final targetId = e['target_id']?.toString() ?? '';

    return AnimatedSize(
      duration: CoolMotion.quick,
      curve: Curves.easeOutCubic,
      child: AdminActivityTile(
        title: '$displayActor · ${action.toUpperCase()}',
        subtitle: '$targetTable${targetId.isNotEmpty ? ' · $targetId' : ''}',
        meta: _formatTimestamp(e['created_at']?.toString()),
        icon: _actionIcon,
        tone: _tone,
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _expanded = !_expanded);
        },
        badges: [
          AdminStatusChip(label: action.toUpperCase(), tone: _tone),
          AdminStatusChip(
            label: _expanded ? context.l10n.adminAuditExpanded : context.l10n.adminAuditCollapsed,
            tone: AdminTone.neutral,
            icon: _expanded
                ? CoolIcons.expandLess
                : CoolIcons.expandMore,
          ),
        ],
        expanded: _expanded,
        expandedChild: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (e['old_data'] != null) ...[
              Text(
                context.l10n.adminAuditPrevious,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.danger,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: CoolSpace.x1),
              _JsonPreview(data: e['old_data']),
              const SizedBox(height: CoolSpace.x3),
            ],
            if (e['new_data'] != null) ...[
              Text(
                context.l10n.adminAuditNew,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.success,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: CoolSpace.x1),
              _JsonPreview(data: e['new_data']),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatTimestamp(String? ts) {
    if (ts == null) return '';
    final dt = DateTime.tryParse(ts);
    if (dt == null) return ts;
    final local = dt.toLocal();
    return '${local.day}/${local.month} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _JsonPreview extends StatelessWidget {
  const _JsonPreview({required this.data});
  final dynamic data;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final text = data is Map
        ? (data as Map).entries
              .take(8)
              .map((e) => '${e.key}: ${e.value}')
              .join('\n')
        : data.toString();

    return AdminPanelSurface(
      backgroundColor: colors.inputSurface,
      padding: CoolSpace.denseSectionPadding.copyWith(
        top: CoolSpace.x2 + 2,
        bottom: CoolSpace.x2 + 2,
      ),
      radius: CoolRadii.md,
      child: Text(
        text,
        style: context.coolText.mono(
          theme.textTheme.labelSmall?.copyWith(color: colors.tertiaryText),
          height: 1.4,
        ),
        maxLines: 8,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
