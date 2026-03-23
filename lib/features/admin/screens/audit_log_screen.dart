import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../providers/admin_providers.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/widgets/cool_screen_background.dart';

EdgeInsets _auditHorizontalPadding() =>
    CoolSpace.sectionPadding.copyWith(top: 0, bottom: 0);

EdgeInsets _auditLogListPadding() =>
    CoolSpace.scaffoldPadding.copyWith(bottom: CoolSpace.x7);

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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final logsAsync = ref.watch(adminAuditLogProvider(_selectedAction));

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
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: _auditHorizontalPadding(),
              child: Semantics(
                header: true,
                child: Text(
                  'Audit Log',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    color: colors.primaryText,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: _auditHorizontalPadding(),
              child: Text(
                'Who changed what and when',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.secondaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: CoolSpace.x4),
            SizedBox(
              height: 48,
              child: ListView.separated(
                padding: _auditHorizontalPadding(),
                scrollDirection: Axis.horizontal,
                itemCount: _actionFilters.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final action = _actionFilters[index];
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
                      color: isSelected
                          ? colors.accentStrong
                          : colors.secondaryText,
                    ),
                    side: BorderSide(
                      color: isSelected ? colors.accent : colors.border,
                    ),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(
                        Radius.circular(CoolRadii.pill),
                      ),
                    ),
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
            ),
            const SizedBox(height: CoolSpace.x4),
            Expanded(
              child: CoolAsyncView<List<Map<String, dynamic>>>(
                value: logsAsync,
                onRetry: () =>
                    ref.invalidate(adminAuditLogProvider(_selectedAction)),
                loadingWidget: const Padding(
                  padding: CoolSpace.scaffoldPadding,
                  child: CoolSkeletonList(itemCount: 6),
                ),
                emptyCheck: (logs) => logs.isEmpty,
                emptyWidget: const CoolEmptyView(
                  message: 'No audit entries yet',
                  icon: Icons.history_rounded,
                ),
                builder: (logs) {
                  return ListView.separated(
                    padding: _auditLogListPadding(),
                    itemCount: logs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) =>
                        _AuditEntryTile(entry: logs[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Audit entry tile
// ═══════════════════════════════════════════════════════════════

class _AuditEntryTile extends StatefulWidget {
  const _AuditEntryTile({required this.entry});
  final Map<String, dynamic> entry;

  @override
  State<_AuditEntryTile> createState() => _AuditEntryTileState();
}

class _AuditEntryTileState extends State<_AuditEntryTile> {
  bool _expanded = false;

  Color _actionColor(CoolSemanticColors colors) {
    switch (widget.entry['action']?.toString()) {
      case 'create':
        return colors.success;
      case 'update':
        return colors.info;
      case 'delete':
        return colors.danger;
      default:
        return colors.neutral;
    }
  }

  IconData get _actionIcon {
    switch (widget.entry['action']?.toString()) {
      case 'create':
        return Icons.add_circle_outline_rounded;
      case 'update':
        return Icons.edit_rounded;
      case 'delete':
        return Icons.delete_outline_rounded;
      default:
        return Icons.info_outline_rounded;
    }
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
        : 'Unknown';
    final action = e['action']?.toString() ?? '';
    final targetTable = e['target_table']?.toString() ?? '';
    final targetId = e['target_id']?.toString() ?? '';
    final createdAt = _formatTimestamp(e['created_at']?.toString());
    final actionColor = _actionColor(colors);

    return AnimatedSize(
      duration: CoolMotion.quick,
      curve: Curves.easeOutCubic,
      child: CoolCard(
        backgroundColor: colors.operationalSurface,
        useGradient: false,
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _expanded = !_expanded);
        },
        semanticsLabel:
            'Audit entry ${action.toUpperCase()} by $displayActor for $targetTable',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: actionColor.withValues(alpha: 0.12),
                    borderRadius: const BorderRadius.all(
                      Radius.circular(CoolRadii.xs),
                    ),
                  ),
                  child: Icon(_actionIcon, size: 16, color: actionColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$displayActor · ${action.toUpperCase()}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colors.primaryText,
                        ),
                      ),
                      Text(
                        '$targetTable${targetId.isNotEmpty ? ' · $targetId' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.tertiaryText,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Text(
                  createdAt,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.tertiaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 18,
                  color: colors.tertiaryText,
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: CoolSpace.x3),
              Divider(height: 1, color: colors.divider),
              const SizedBox(height: CoolSpace.x3),
              if (e['old_data'] != null) ...[
                Text(
                  'Previous',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.danger,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: CoolSpace.x1),
                _JsonPreview(data: e['old_data']),
                const SizedBox(height: 10),
              ],
              if (e['new_data'] != null) ...[
                Text(
                  'New',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.success,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: CoolSpace.x1),
                _JsonPreview(data: e['new_data']),
              ],
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

    return Container(
      width: double.infinity,
      padding: CoolSpace.denseSectionPadding.copyWith(
        top: CoolSpace.x2 + 2,
        bottom: CoolSpace.x2 + 2,
      ),
      decoration: BoxDecoration(
        color: colors.inputSurface,
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.xs)),
        border: Border.all(color: colors.border),
      ),
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
