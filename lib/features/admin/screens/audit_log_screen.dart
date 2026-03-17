import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../providers/admin_providers.dart';
import '../../../core/l10n/l10n.dart';

/// Audit log viewer — shows all admin actions captured by DB triggers.
class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  String? _selectedAction;

  static const _actionFilters = [
    null,       // all
    'create',
    'update',
    'delete',
  ];

  @override
  Widget build(BuildContext context) {
    final logsAsync = ref.watch(adminAuditLogProvider(_selectedAction));

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: context.l10n.back,
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.text),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
            child: Text(
              'Audit Log',
              style: GoogleFonts.dmSans(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
            child: Text(
              'Who did what, when',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.text3,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Action filter chips ──────────────────────────────────
          SizedBox(
            height: 36,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 18),
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
                  label: Text(label),
                  selected: isSelected,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedAction = action);
                  },
                  backgroundColor: AppColors.bg,
                  selectedColor: AppColors.blue.withValues(alpha: 0.2),
                  labelStyle: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? AppColors.blue : AppColors.text3,
                  ),
                  side: BorderSide(
                    color: isSelected ? AppColors.blue : AppColors.border,
                  ),
                  visualDensity: VisualDensity.compact,
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // ── Log entries ──────────────────────────────────────────
          Expanded(
            child: CoolAsyncView<List<Map<String, dynamic>>>(
              value: logsAsync,
              onRetry: () =>
                  ref.invalidate(adminAuditLogProvider(_selectedAction)),
              loadingWidget: const Padding(
                padding: EdgeInsets.fromLTRB(18, 0, 18, 16),
                child: CoolSkeletonList(itemCount: 6),
              ),
              emptyCheck: (logs) => logs.isEmpty,
              emptyWidget: const CoolEmptyView(
                message: 'No audit entries yet',
                icon: Icons.history_rounded,
              ),
              builder: (logs) {
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
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

  Color get _actionColor {
    switch (widget.entry['action']?.toString()) {
      case 'create':
        return Colors.green;
      case 'update':
        return AppColors.blue;
      case 'delete':
        return Colors.red;
      default:
        return AppColors.text3;
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

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _expanded = !_expanded);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _actionColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_actionIcon, size: 16, color: _actionColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$displayActor · ${action.toUpperCase()}',
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      Text(
                        '$targetTable${targetId.isNotEmpty ? ' · $targetId' : ''}',
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Text(
                  createdAt,
                  style: GoogleFonts.dmSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    color: AppColors.text3,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 18,
                  color: AppColors.text3,
                ),
              ],
            ),

            // ── Expanded details ──────────────────────────────────
            if (_expanded) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              if (e['old_data'] != null) ...[
                Text(
                  'Previous',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.red.shade300,
                  ),
                ),
                const SizedBox(height: 4),
                _JsonPreview(data: e['old_data']),
                const SizedBox(height: 10),
              ],
              if (e['new_data'] != null) ...[
                Text(
                  'New',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.green.shade300,
                  ),
                ),
                const SizedBox(height: 4),
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
    final text = data is Map
        ? (data as Map)
            .entries
            .take(8)
            .map((e) => '${e.key}: ${e.value}')
            .join('\n')
        : data.toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        text,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 10,
          fontWeight: FontWeight.w400,
          color: AppColors.text3,
        ),
        maxLines: 8,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}