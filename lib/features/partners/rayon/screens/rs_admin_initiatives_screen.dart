import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/cool_async_view.dart';
import '../../../../shared/widgets/cool_empty_view.dart';
import '../../../../shared/widgets/cool_skeleton.dart';
import '../../providers/rayon_sports_provider.dart';
import '../models/rs_models.dart';
import '../providers/rs_admin_provider.dart';
import '../widgets/rs_admin_shell.dart';

/// Admin screen for managing RS initiatives — CRUD, toggle active, progress.
class RsAdminInitiativesScreen extends ConsumerStatefulWidget {
  const RsAdminInitiativesScreen({super.key});

  @override
  ConsumerState<RsAdminInitiativesScreen> createState() =>
      _RsAdminInitiativesScreenState();
}

class _RsAdminInitiativesScreenState
    extends ConsumerState<RsAdminInitiativesScreen> {
  String _categoryFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final initAsync = ref.watch(rsAdminInitiativesProvider);

    return RsAdminShell(
      title: 'Initiatives',
      subtitle:
          'Track and manage community causes',
      floatingActionButton: Semantics(
        button: true,
        label: 'Add initiative',
        hint: 'New initiative',
        child: FloatingActionButton(
          backgroundColor: AppColors.rsBlue,
          onPressed: () => _showForm(context),
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
      metrics: [
        RsAdminMetric(
          label: 'causes',
          value:
              initAsync.whenOrNull(data: (items) => '${items.length}') ?? '...',
        ),
        RsAdminMetric(
          label: 'active',
          value:
              initAsync.whenOrNull(
                data: (items) =>
                    '${items.where((initiative) => initiative.isActive).length}',
              ) ??
              '...',
        ),
      ],
      controls: SizedBox(
        height: 36,
        child: initAsync.whenOrNull(
          data: (items) {
            final categories = <String>{'all'};
            for (final i in items) {
              categories.add(i.category.value);
            }
            return ListView(
              scrollDirection: Axis.horizontal,
              children: categories.map((cat) {
                final label = cat == 'all'
                    ? 'All'
                    : '${cat[0].toUpperCase()}${cat.substring(1)}';
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _categoryFilter = cat),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _categoryFilter == cat
                            ? AppColors.rsBlue
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _categoryFilter == cat
                              ? AppColors.rsBlue
                              : AppColors.border,
                        ),
                      ),
                      child: Text(
                        label,
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _categoryFilter == cat
                              ? Colors.white
                              : AppColors.text2,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ) ?? const SizedBox.shrink(),
      ),
      child: CoolAsyncView<List<RsInitiative>>(
        value: initAsync,
        onRetry: () => ref.invalidate(rsAdminInitiativesProvider),
        loadingWidget: const Padding(
          padding: EdgeInsets.all(16),
          child: CoolSkeletonList(itemCount: 4),
        ),
        emptyCheck: (initiatives) => initiatives.isEmpty,
        emptyWidget: const CoolEmptyView(
          message: 'No initiatives created yet',
          icon: Icons.flag_outlined,
          isPremium: true,
        ),
        builder: (initiatives) {
          final filtered = _categoryFilter == 'all'
              ? initiatives
              : initiatives
                    .where((i) => i.category.value == _categoryFilter)
                    .toList();
          if (filtered.isEmpty) {
            return const CoolEmptyView(
              message: 'No initiatives in this category',
              icon: Icons.filter_list_off_rounded,
              isPremium: true,
            );
          }
          return ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: filtered.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final init = filtered[index];
              return _InitiativeTile(
                initiative: init,
                onToggleActive: () => _toggleActive(init),
                onEdit: () => _showForm(context, initiative: init),
                onViewContributors: () =>
                    _showContributors(context, init),
                onDelete: () => _deleteInitiative(init),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _toggleActive(RsInitiative init) async {
    final repo = ref.read(rayonSportsRepositoryProvider);
    await repo.toggleInitiativeActive(init.id, isActive: !init.isActive);
    ref.invalidate(rsAdminInitiativesProvider);
  }

  Future<void> _deleteInitiative(RsInitiative init) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Delete Initiative?',
          style: GoogleFonts.dmSans(
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        content: Text(
          'Delete "${init.title}"? This cannot be undone.',
          style: GoogleFonts.dmSans(color: AppColors.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final repo = ref.read(rayonSportsRepositoryProvider);
      await repo.deleteInitiative(init.id);
      ref.invalidate(rsAdminInitiativesProvider);
      if (mounted) HapticFeedback.mediumImpact();
    }
  }



  void _showContributors(BuildContext context, RsInitiative initiative) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (ctx, scrollCtrl) => _ContributorsSheet(
          initiative: initiative,
          scrollController: scrollCtrl,
        ),
      ),
    );
  }

  void _showForm(BuildContext context, {RsInitiative? initiative}) {
    final isEdit = initiative != null;
    final titleCtrl = TextEditingController(text: initiative?.title);
    final descCtrl = TextEditingController(text: initiative?.description);
    final categoryCtrl = TextEditingController(
      text: initiative?.category.value ?? 'community',
    );
    final targetCtrl = TextEditingController(
      text: initiative?.targetAmount.toString() ?? '500000',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isEdit ? 'Edit Initiative' : 'New Initiative',
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 16),
              _Field(controller: titleCtrl, label: 'Title'),
              _Field(controller: descCtrl, label: 'Description', maxLines: 3),
              _Field(controller: categoryCtrl, label: 'Category'),
              _Field(
                controller: targetCtrl,
                label: 'Target Amount (RWF)',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.rsBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () async {
                  final repo = ref.read(rayonSportsRepositoryProvider);
                  if (isEdit) {
                    await repo
                        .updateInitiative(initiative.id, <String, dynamic>{
                          'title': titleCtrl.text,
                          'description': descCtrl.text,
                          'category': categoryCtrl.text,
                          'target_amount':
                              int.tryParse(targetCtrl.text) ?? 500000,
                        });
                  } else {
                    await repo.createInitiative(
                      title: titleCtrl.text,
                      description: descCtrl.text,
                      category: categoryCtrl.text,
                      targetAmount: int.tryParse(targetCtrl.text) ?? 500000,
                      endsAt: DateTime.now().add(const Duration(days: 90)),
                    );
                  }
                  ref.invalidate(rsAdminInitiativesProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(isEdit ? 'Update' : 'Create'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InitiativeTile extends StatelessWidget {
  const _InitiativeTile({
    required this.initiative,
    required this.onToggleActive,
    required this.onEdit,
    required this.onViewContributors,
    required this.onDelete,
  });
  final RsInitiative initiative;
  final VoidCallback onToggleActive;
  final VoidCallback onEdit;
  final VoidCallback onViewContributors;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final progress = initiative.targetAmount > 0
        ? (initiative.raisedAmount / initiative.targetAmount).clamp(0.0, 1.0)
        : 0.0;
    final endsStr = initiative.endsAt != null
        ? DateFormat('d MMM yyyy').format(initiative.endsAt!)
        : 'No end date';
    final fmtRaised = NumberFormat.compact().format(initiative.raisedAmount);
    final fmtTarget = NumberFormat.compact().format(initiative.targetAmount);

    return Semantics(
      container: true,
      label:
          'Initiative ${initiative.title}. ${initiative.isActive ?'Active' : 'Inactive'}. '
          '$fmtRaised of $fmtTarget Rwandan francs raised. '
          '${initiative.supporterCount} supporters. Ends $endsStr.',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    initiative.title,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ),
                Semantics(
                  label: initiative.isActive
                      ? 'Status active'
                      : 'Status inactive',
                  child: ExcludeSemantics(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: initiative.isActive
                            ? AppColors.accent.withValues(alpha: 0.15)
                            : AppColors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        initiative.isActive ? 'ACTIVE' : 'INACTIVE',
                        style: GoogleFonts.dmSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: initiative.isActive
                              ? AppColors.accent
                              : AppColors.red,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (initiative.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                initiative.description,
                style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.text3),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            Semantics(
              label:
                  'Progress ${(progress * 100).round()} percent.'
                  '$fmtRaised raised of $fmtTarget Rwandan francs target.',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: AppColors.surface2,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.accent,
                  ),
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$fmtRaised / $fmtTarget RWF · ${initiative.supporterCount} supporters',
              style: GoogleFonts.dmSans(fontSize: 10, color: AppColors.text3),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _Btn(
                  icon: initiative.isActive ? Icons.pause : Icons.play_arrow,
                  label: initiative.isActive ? 'Deactivate' : 'Activate',
                  onTap: onToggleActive,
                ),
                const SizedBox(width: 12),
                _Btn(icon: Icons.edit, label: 'Edit', onTap: onEdit),
                const SizedBox(width: 12),
                _Btn(
                  icon: Icons.people_outline_rounded,
                  label: '${initiative.supporterCount} supporters',
                  onTap: onViewContributors,
                ),
                const SizedBox(width: 12),
                _Btn(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  onTap: onDelete,
                  color: AppColors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({required this.icon, required this.label, required this.onTap, this.color});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.text2;
    return Semantics(
      button: true,
      label: label,
      hint: '${label.toLowerCase()} initiative',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: c),
            const SizedBox(width: 3),
            Text(
              label,
              style: GoogleFonts.dmSans(fontSize: 10, color: c),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.maxLines = 1,
  });
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        textField: true,
        label: label,
        hint: 'Enter $label',
        child: TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: GoogleFonts.dmSans(color: AppColors.text, fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: GoogleFonts.dmSans(
              color: AppColors.text3,
              fontSize: 13,
            ),
            filled: true,
            fillColor: AppColors.surface2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _ContributorsSheet extends ConsumerWidget {
  const _ContributorsSheet({
    required this.initiative,
    required this.scrollController,
  });
  final RsInitiative initiative;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contributionsAsync =
        ref.watch(rsAdminInitiativeContributionsProvider(initiative.id));
    final moneyFmt = NumberFormat.compact();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            initiative.title,
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${initiative.supporterCount} supporters · ${moneyFmt.format(initiative.raisedAmount)} RWF raised',
            style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.text3),
          ),
          const SizedBox(height: 16),
          Text(
            'Recent Contributions',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: contributionsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Failed to load contributions',
                  style: GoogleFonts.dmSans(color: AppColors.text3),
                ),
              ),
              data: (contributions) {
                if (contributions.isEmpty) {
                  return Center(
                    child: Text(
                      'No contributions yet',
                      style: GoogleFonts.dmSans(color: AppColors.text3),
                    ),
                  );
                }
                return ListView.separated(
                  controller: scrollController,
                  itemCount: contributions.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final c = contributions[index];
                    final dateStr =
                        DateFormat('d MMM, HH:mm').format(c.createdAt);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.supporterName ?? 'Anonymous',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.text,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  dateStr,
                                  style: GoogleFonts.dmSans(
                                    fontSize: 11,
                                    color: AppColors.text3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${moneyFmt.format(c.amount)} RWF',
                            style: GoogleFonts.dmSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accent,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
