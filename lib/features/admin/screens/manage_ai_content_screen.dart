import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/providers/supabase_client_provider.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../home/models/nexus_recommendation.dart';
import '../../home/providers/nexus_provider.dart';
import '../../../core/l10n/l10n.dart';
import '../widgets/ai_content_edit_sheet.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';
import '../../../shared/widgets/cool_screen_background.dart';

// ── Providers ────────────────────────────────────────────────

final _aiContentFilterProvider = StateProvider<AiContentStatus?>((ref) => null);

final _aiContentListProvider =
    FutureProvider.autoDispose<List<NexusRecommendation>>((ref) async {
  final filter = ref.watch(_aiContentFilterProvider);
  final repo = ref.read(nexusRepositoryProvider);
  return repo.fetchAll(statusFilter: filter);
});

final _aiGenConfigProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final client = ref.read(supabaseClientProvider);
  final rows = await client
      .from('ai_content_generation_config')
      .select()
      .limit(1);
  if (rows.isEmpty) return null;
  return rows.first;
});

// ── Screen ───────────────────────────────────────────────────

/// Admin CRUD screen for AI-generated content with approval workflow.
class ManageAiContentScreen extends ConsumerWidget {
  const ManageAiContentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.coolPalette;
    final contentAsync = ref.watch(_aiContentListProvider);
    final activeFilter = ref.watch(_aiContentFilterProvider);
    final genConfigAsync = ref.watch(_aiGenConfigProvider);

    return CoolScreenBackground(


      showGlow: false,


      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: context.l10n.back,
          icon: Icon(Icons.arrow_back_rounded, color: palette.text),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: palette.accent,
        onPressed: () => _showEditSheet(context, ref, null),
        child: const Icon(Icons.add_rounded, color: Colors.black),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
            child: Text(
              'AI Content',
              style: GoogleFonts.dmSans(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                color: palette.text,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
            child: Text(
              'AI-generated UI elements with admin approval gate.',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: palette.text3,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Generation Controls ──────────────────────────────
          genConfigAsync.when(
            data: (config) => config == null
                ? const SizedBox.shrink()
                : _GenerationControlsCard(
                    isEnabled: config['is_enabled'] as bool? ?? false,
                    lastGeneratedAt: config['last_generated_at'] != null
                        ? DateTime.tryParse(
                            config['last_generated_at'].toString())
                        : null,
                    onToggle: (enabled) =>
                        _toggleGeneration(context, ref, enabled),
                    onGenerateNow: () => _triggerGeneration(context, ref),
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),

          // ── Status filter chips ──────────────────────────────
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              children: [
                _FilterChip(
                  label: 'All',
                  isSelected: activeFilter == null,
                  onTap: () =>
                      ref.read(_aiContentFilterProvider.notifier).state = null,
                ),
                const SizedBox(width: 8),
                ...AiContentStatus.values.map((status) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _FilterChip(
                        label: status.label,
                        isSelected: activeFilter == status,
                        color: status.color,
                        onTap: () => ref
                            .read(_aiContentFilterProvider.notifier)
                            .state = status,
                      ),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Content list ─────────────────────────────────────
          Expanded(
            child: contentAsync.when(
              data: (items) => items.isEmpty
                  ? Center(
                      child: Text(
                        'No content found',
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          color: palette.text3,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(_aiContentListProvider);
                      },
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 96),
                        itemCount: items.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return _AiContentCard(
                            item: item,
                            onEdit: () =>
                                _showEditSheet(context, ref, item),
                            onApprove: item.status ==
                                    AiContentStatus.pendingReview
                                ? () => _approve(context, ref, item.id)
                                : null,
                            onReject: item.status ==
                                    AiContentStatus.pendingReview
                                ? () => _reject(context, ref, item.id)
                                : null,
                            onToggle: item.status ==
                                    AiContentStatus.approved
                                ? () =>
                                    _toggleActive(context, ref, item)
                                : null,
                            onDelete: () =>
                                _delete(context, ref, item),
                          );
                        },
                      ),
                    ),
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Error: $e',
                  style: GoogleFonts.dmSans(color: palette.text3),
                ),
              ),
            ),
          ),
        ],
      ),
    ),


    );
  }

  // ── Actions ──────────────────────────────────────────────────

  Future<void> _approve(
      BuildContext context, WidgetRef ref, String id) async {
    try {
      HapticFeedback.mediumImpact();
      final repo = ref.read(nexusRepositoryProvider);
      await repo.approve(id);
      ref.invalidate(_aiContentListProvider);
      if (context.mounted) {
        CoolToast.info(context, 'Content approved ✓');
      }
    } catch (e) {
      if (context.mounted) {
        CoolToast.error(context, 'Approve failed: $e');
      }
    }
  }

  Future<void> _reject(
      BuildContext context, WidgetRef ref, String id) async {
    try {
      HapticFeedback.mediumImpact();
      final repo = ref.read(nexusRepositoryProvider);
      await repo.reject(id);
      ref.invalidate(_aiContentListProvider);
      if (context.mounted) {
        CoolToast.info(context, 'Content rejected');
      }
    } catch (e) {
      if (context.mounted) {
        CoolToast.error(context, 'Reject failed: $e');
      }
    }
  }

  Future<void> _toggleActive(
      BuildContext context, WidgetRef ref, NexusRecommendation item) async {
    try {
      HapticFeedback.selectionClick();
      final repo = ref.read(nexusRepositoryProvider);
      await repo.toggleActive(item.id, isActive: !item.isActive);
      ref.invalidate(_aiContentListProvider);
      if (context.mounted) {
        CoolToast.info(context,
            item.isActive ? 'Deactivated' : 'Activated');
      }
    } catch (e) {
      if (context.mounted) {
        CoolToast.error(context, 'Toggle failed: $e');
      }
    }
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, NexusRecommendation item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.deleteContent),
        content: Text('Delete "${item.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                Text(context.l10n.delete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final repo = ref.read(nexusRepositoryProvider);
      await repo.delete(item.id);
      ref.invalidate(_aiContentListProvider);
      if (context.mounted) {
        CoolToast.info(context, 'Deleted');
      }
    } catch (e) {
      if (context.mounted) {
        CoolToast.error(context, 'Delete failed: $e');
      }
    }
  }

  void _showEditSheet(
      BuildContext context, WidgetRef ref, NexusRecommendation? item) {
    showCoolBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => EditAiContentSheet(
        initial: item,
        onSave: (saved) async {
          try {
            final repo = ref.read(nexusRepositoryProvider);
            await repo.upsert(saved);
            ref.invalidate(_aiContentListProvider);
            if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
            if (context.mounted) {
              CoolToast.info(context,
                      item == null ? 'Content created' : 'Content updated');
            }
          } catch (e) {
            if (context.mounted) {
              CoolToast.error(context, 'Save failed: $e');
            }
          }
        },
      ),
    );
  }

  Future<void> _toggleGeneration(
      BuildContext context, WidgetRef ref, bool enabled) async {
    try {
      HapticFeedback.mediumImpact();
      await ref.read(supabaseClientProvider)
          .from('ai_content_generation_config')
          .update({
        'is_enabled': enabled,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).not('id', 'is', null);
      ref.invalidate(_aiGenConfigProvider);
      if (context.mounted) {
        CoolToast.info(context,
            enabled ? 'Auto-generation enabled' : 'Auto-generation disabled');
      }
    } catch (e) {
      if (context.mounted) {
        CoolToast.error(context, 'Toggle failed: $e');
      }
    }
  }

  Future<void> _triggerGeneration(
      BuildContext context, WidgetRef ref) async {
    try {
      HapticFeedback.mediumImpact();
      CoolToast.info(context, 'Generating content…');
      final response = await ref.read(supabaseClientProvider).functions
          .invoke('generate-ai-content', queryParameters: {'manual': 'true'});
      ref.invalidate(_aiContentListProvider);
      ref.invalidate(_aiGenConfigProvider);
      if (context.mounted) {
        final data = response.data;
        if (data != null && data['success'] == true) {
          CoolToast.info(
              context, 'Generated: ${data['title'] ?? 'new content'} ✓');
        } else {
          CoolToast.error(context,
              'Generation issue: ${data?['reason'] ?? 'unknown'}');
        }
      }
    } catch (e) {
      if (context.mounted) {
        CoolToast.error(context, 'Generation failed: $e');
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// Generation Controls Card
// ═══════════════════════════════════════════════════════════════

class _GenerationControlsCard extends StatefulWidget {
  const _GenerationControlsCard({
    required this.isEnabled,
    required this.lastGeneratedAt,
    required this.onToggle,
    required this.onGenerateNow,
  });

  final bool isEnabled;
  final DateTime? lastGeneratedAt;
  final ValueChanged<bool> onToggle;
  final VoidCallback onGenerateNow;

  @override
  State<_GenerationControlsCard> createState() =>
      _GenerationControlsCardState();
}

class _GenerationControlsCardState extends State<_GenerationControlsCard> {
  bool _isGenerating = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final lastGen = widget.lastGeneratedAt;
    final lastLabel = lastGen != null
        ? '${lastGen.day}/${lastGen.month}/${lastGen.year} ${lastGen.hour}:${lastGen.minute.toString().padLeft(2, '0')}'
        : 'Never';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: CoolCard(
        useGradient: false,
        padding: const EdgeInsets.all(16),
        borderRadius: 20,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.smart_toy_rounded,
                    size: 20, color: palette.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Auto-Generation',
                    style: GoogleFonts.dmSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: palette.text,
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: widget.isEnabled,
                  activeTrackColor: palette.accent,
                  onChanged: widget.onToggle,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.isEnabled
                  ? 'Generates 1 new content item every 12 hours'
                  : 'Disabled \u2014 no content auto-generated',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                color: palette.text3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Last generated: $lastLabel',
              style: GoogleFonts.dmSans(
                fontSize: 11,
                color: palette.text3,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isGenerating
                    ? null
                    : () async {
                        setState(() => _isGenerating = true);
                        widget.onGenerateNow();
                        await Future<void>.delayed(
                            const Duration(seconds: 2));
                        if (mounted) {
                          setState(() => _isGenerating = false);
                        }
                      },
                icon: _isGenerating
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: palette.accent,
                        ),
                      )
                    : const Icon(Icons.auto_awesome_rounded, size: 16),
                label: Text(
                  _isGenerating ? 'Generating\u2026' : 'Generate Now',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.accent,
                  side: BorderSide(color: palette.accent),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Filter chip
// ═══════════════════════════════════════════════════════════════

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final chipColor = color ?? palette.accent;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? chipColor.withValues(alpha: 0.2)
              : palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? chipColor.withValues(alpha: 0.5)
                : palette.border,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isSelected ? chipColor : palette.text2,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Content card
// ═══════════════════════════════════════════════════════════════

class _AiContentCard extends StatelessWidget {
  const _AiContentCard({
    required this.item,
    required this.onEdit,
    this.onApprove,
    this.onReject,
    this.onToggle,
    this.onDelete,
  });

  final NexusRecommendation item;
  final VoidCallback onEdit;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onToggle;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return CoolCard(
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: item.status.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  item.status.label.toUpperCase(),
                  style: GoogleFonts.dmSans(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: item.status.color,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: palette.surface2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  item.contentType.label,
                  style: GoogleFonts.dmSans(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: palette.text3,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Spacer(),
              if (!item.isActive && item.status == AiContentStatus.approved)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'INACTIVE',
                    style: GoogleFonts.dmSans(
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      color: Colors.red,
                    ),
                  ),
                ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded,
                    size: 20, color: palette.text3),
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      onEdit();
                    case 'toggle':
                      onToggle?.call();
                    case 'delete':
                      onDelete?.call();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                      value: 'edit',
                      child: Text(context.l10n.editChildTextedit)),
                  if (onToggle != null)
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(item.isActive ? 'Deactivate' : 'Activate'),
                    ),
                  if (onDelete != null)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete',
                          style: TextStyle(color: Colors.red)),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(item.iconEmoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.title,
                  style: GoogleFonts.dmSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: palette.text,
                  ),
                ),
              ),
            ],
          ),
          if (item.subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              item.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: palette.text2,
                height: 1.4,
              ),
            ),
          ],
          if (onApprove != null || onReject != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                if (onApprove != null)
                  Expanded(
                    child: _ActionButton(
                      label: 'Approve',
                      icon: Icons.check_circle_rounded,
                      color: Colors.green,
                      onTap: onApprove!,
                    ),
                  ),
                if (onApprove != null && onReject != null)
                  const SizedBox(width: 10),
                if (onReject != null)
                  Expanded(
                    child: _ActionButton(
                      label: 'Reject',
                      icon: Icons.cancel_rounded,
                      color: Colors.red,
                      onTap: onReject!,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Action button
// ═══════════════════════════════════════════════════════════════

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}