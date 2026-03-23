import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/tab_pill.dart';
import '../providers/admin_ai_content_providers.dart';
import '../widgets/ai_content_edit_sheet.dart';
import '../../home/models/nexus_recommendation.dart';
import '../../home/providers/nexus_provider.dart';

part '../widgets/manage_ai_content_parts.dart';

EdgeInsets _manageAiContentHeaderPadding() =>
    CoolSpace.pagePadding.copyWith(top: 0, bottom: 0);

EdgeInsets _manageAiContentLoadingPadding() => CoolSpace.scaffoldPadding;

EdgeInsets _manageAiContentListPadding() => CoolSpace.scaffoldPadding;

EdgeInsets _manageAiContentTabSpacing() => CoolSpace.sectionPadding.copyWith(
  left: 0,
  right: CoolSpace.x2,
  top: 0,
  bottom: 0,
);

// ── Providers ────────────────────────────────────────────────

final _aiContentFilterProvider = StateProvider<AiContentStatus?>((ref) => null);

final _aiContentListProvider =
    FutureProvider.autoDispose<List<NexusRecommendation>>((ref) async {
      final filter = ref.watch(_aiContentFilterProvider);
      final repo = ref.read(nexusRepositoryProvider);
      return repo.fetchAll(statusFilter: filter);
    });

// ── Screen ───────────────────────────────────────────────────

/// Admin CRUD screen for AI-generated content with approval workflow.
class ManageAiContentScreen extends ConsumerWidget {
  const ManageAiContentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final contentAsync = ref.watch(_aiContentListProvider);
    final activeFilter = ref.watch(_aiContentFilterProvider);
    final genConfigAsync = ref.watch(adminAiContentGenerationConfigProvider);

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
          label: 'Create AI content',
          hint: 'Open AI content form',
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
              padding: _manageAiContentHeaderPadding(),
              child: Semantics(
                header: true,
                child: Text(
                  'AI Content',
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
              padding: _manageAiContentHeaderPadding(),
              child: Text(
                'Review, approve, publish.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.secondaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: CoolSpace.x4),
            genConfigAsync.when(
              data: (config) => config == null
                  ? const SizedBox.shrink()
                  : _GenerationControlsCard(
                      isEnabled: config.isEnabled,
                      intervalHours: config.intervalHours,
                      lastGeneratedAt: config.lastGeneratedAt,
                      onToggle: (enabled) =>
                          _toggleGeneration(context, ref, enabled),
                      onGenerateNow: () => _triggerGeneration(context, ref),
                    ),
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
            if (genConfigAsync.asData?.value != null)
              const SizedBox(height: CoolSpace.x4),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: _manageAiContentHeaderPadding(),
                children: [
                  TabPill(
                    label: 'All',
                    isActive: activeFilter == null,
                    onTap: () =>
                        ref.read(_aiContentFilterProvider.notifier).state =
                            null,
                  ),
                  const SizedBox(width: 8),
                  ...AiContentStatus.values.map(
                    (status) => Padding(
                      padding: _manageAiContentTabSpacing(),
                      child: TabPill(
                        label: status.label,
                        isActive: activeFilter == status,
                        onTap: () =>
                            ref.read(_aiContentFilterProvider.notifier).state =
                                status,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: CoolSpace.x4),
            Expanded(
              child: CoolAsyncView<List<NexusRecommendation>>(
                value: contentAsync,
                onRetry: () => ref.invalidate(_aiContentListProvider),
                loadingWidget: Padding(
                  padding: _manageAiContentLoadingPadding(),
                  child: const CoolSkeletonList(itemCount: 4),
                ),
                emptyCheck: (items) => items.isEmpty,
                emptyWidget: const CoolEmptyView(
                  message: 'No content found',
                  icon: Icons.auto_awesome_outlined,
                ),
                builder: (items) => RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(_aiContentListProvider);
                  },
                  child: ListView.separated(
                    padding: _manageAiContentListPadding(),
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: CoolSpace.x3),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _AiContentCard(
                        item: item,
                        onEdit: () => _showEditSheet(context, ref, item),
                        onApprove: item.status == AiContentStatus.pendingReview
                            ? () => _approve(context, ref, item.id)
                            : null,
                        onReject: item.status == AiContentStatus.pendingReview
                            ? () => _reject(context, ref, item.id)
                            : null,
                        onToggle: item.status == AiContentStatus.approved
                            ? () => _toggleActive(context, ref, item)
                            : null,
                        onDelete: () => _delete(context, ref, item),
                      );
                    },
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

  Future<void> _approve(BuildContext context, WidgetRef ref, String id) async {
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

  Future<void> _reject(BuildContext context, WidgetRef ref, String id) async {
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
    BuildContext context,
    WidgetRef ref,
    NexusRecommendation item,
  ) async {
    try {
      HapticFeedback.selectionClick();
      final repo = ref.read(nexusRepositoryProvider);
      await repo.toggleActive(item.id, isActive: !item.isActive);
      ref.invalidate(_aiContentListProvider);
      if (context.mounted) {
        CoolToast.info(context, item.isActive ? 'Deactivated' : 'Activated');
      }
    } catch (e) {
      if (context.mounted) {
        CoolToast.error(context, 'Toggle failed: $e');
      }
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    NexusRecommendation item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colors = ctx.coolSemanticColors;
        final theme = Theme.of(ctx);
        return AlertDialog(
          backgroundColor: colors.overlaySurface,
          title: Text(context.l10n.deleteContent),
          content: Text('Delete "${item.title}"? This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                context.l10n.delete,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
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
    BuildContext context,
    WidgetRef ref,
    NexusRecommendation? item,
  ) {
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
              CoolToast.info(
                context,
                item == null ? 'Content created' : 'Content updated',
              );
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
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    try {
      HapticFeedback.mediumImpact();
      await ref
          .read(adminAiContentRepositoryProvider)
          .setGenerationEnabled(enabled);
      ref.invalidate(adminAiContentGenerationConfigProvider);
      if (context.mounted) {
        CoolToast.info(
          context,
          enabled ? 'Auto-generation enabled' : 'Auto-generation disabled',
        );
      }
    } catch (e) {
      if (context.mounted) {
        CoolToast.error(context, 'Toggle failed: $e');
      }
    }
  }

  Future<void> _triggerGeneration(BuildContext context, WidgetRef ref) async {
    try {
      HapticFeedback.mediumImpact();
      CoolToast.info(context, 'Generating content…');
      final result = await ref
          .read(adminAiContentRepositoryProvider)
          .triggerManualGeneration();
      ref.invalidate(_aiContentListProvider);
      ref.invalidate(adminAiContentGenerationConfigProvider);
      if (context.mounted) {
        if (result.success) {
          CoolToast.info(
            context,
            'Generated: ${result.title ?? 'new content'} ✓',
          );
        } else {
          CoolToast.error(
            context,
            'Generation issue: ${result.reason ?? 'unknown'}',
          );
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
