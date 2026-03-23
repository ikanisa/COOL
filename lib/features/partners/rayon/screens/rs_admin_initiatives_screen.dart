import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../shared/widgets/cool_async_view.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_empty_view.dart';
import '../../../../shared/widgets/cool_skeleton.dart';
import '../../providers/rayon_sports_provider.dart';
import '../models/rs_models.dart';
import '../providers/rs_admin_provider.dart';
import '../widgets/rs_admin_shell.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../shared/widgets/cool_bottom_sheet.dart';

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
      title: context.l10n.initiatives,
      subtitle:
          'Steer active club causes, funding targets, and supporter momentum from one community board.',
      floatingActionButton: Semantics(
        button: true,
        label: 'Add initiative',
        hint: 'New initiative',
        child: FloatingActionButton(
          backgroundColor: RsColors.rsBlue,
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
        height: 44,
        child:
            initAsync.whenOrNull(
              data: (items) {
                final categories = <String>{'all'};
                final counts = <String, int>{};
                for (final i in items) {
                  categories.add(i.category.value);
                  counts[i.category.value] =
                      (counts[i.category.value] ?? 0) + 1;
                }
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final category = categories.elementAt(index);
                    final label = category == 'all'
                        ? 'All (${items.length})'
                        : '${_title(category)} (${counts[category] ?? 0})';
                    return _InitiativeFilterChip(
                      label: label,
                      isSelected: _categoryFilter == category,
                      onTap: () => setState(() => _categoryFilter = category),
                    );
                  },
                );
              },
            ) ??
            const SizedBox.shrink(),
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
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final init = filtered[index];
              return _InitiativeTile(
                initiative: init,
                onToggleActive: () => _toggleActive(init),
                onEdit: () => _showForm(context, initiative: init),
                onViewContributors: () => _showContributors(context, init),
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
    final colors = context.coolSemanticColors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.elevatedBackground,
        title: Text(
          'Delete Initiative?',
          style: GoogleFonts.dmSans(
            fontWeight: FontWeight.w700,
            color: colors.primaryText,
          ),
        ),
        content: Text(
          'Delete "${init.title}"? This cannot be undone.',
          style: GoogleFonts.dmSans(color: colors.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.delete),
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
    final colors = context.coolSemanticColors;
    showCoolBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.overlaySurface,
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
    final colors = context.coolSemanticColors;
    final isEdit = initiative != null;
    final titleCtrl = TextEditingController(text: initiative?.title);
    final descCtrl = TextEditingController(text: initiative?.description);
    final categoryCtrl = TextEditingController(
      text: initiative?.category.value ?? 'community',
    );
    final targetCtrl = TextEditingController(
      text: initiative?.targetAmount.toString() ?? '500000',
    );

    showCoolBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.overlaySurface,
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
                isEdit ? 'Official Initiative Editor' : 'New Club Initiative',
                style: context.coolText.rayonCondensed(
                  const TextStyle(fontSize: 30),
                  fontWeight: FontWeight.w900,
                  color: colors.primaryText,
                  height: 0.95,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Set the campaign story, funding target, and community category before this cause goes live.',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colors.secondaryText,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: CoolSpace.x4),
              _Field(controller: titleCtrl, label: 'Title'),
              _Field(controller: descCtrl, label: 'Description', maxLines: 3),
              _Field(controller: categoryCtrl, label: 'Category'),
              _Field(
                controller: targetCtrl,
                label: 'Target Amount (RWF)',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: CoolSpace.x4),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: RsColors.rsBlue,
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
    final colors = context.coolSemanticColors;
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
          'Initiative ${initiative.title}. ${initiative.isActive ? 'Active' : 'Inactive'}. '
          '$fmtRaised of $fmtTarget Rwandan francs raised. '
          '${initiative.supporterCount} supporters. Ends $endsStr.',
      child: CoolCard(
        backgroundColor: colors.operationalSurface,
        borderColor: initiative.isActive
            ? colors.success.withValues(alpha: 0.28)
            : colors.border,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        initiative.title,
                        style: context.coolText.rayonCondensed(
                          const TextStyle(fontSize: 28),
                          fontWeight: FontWeight.w900,
                          color: colors.primaryText,
                          height: 0.95,
                        ),
                      ),
                      const SizedBox(height: CoolSpace.x1),
                      Text(
                        initiative.category.value.toUpperCase(),
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: colors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                Semantics(
                  label: initiative.isActive
                      ? 'Status active'
                      : 'Status inactive',
                  child: ExcludeSemantics(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: initiative.isActive
                            ? colors.success.withValues(alpha: 0.15)
                            : colors.danger.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: initiative.isActive
                              ? colors.success.withValues(alpha: 0.28)
                              : colors.danger.withValues(alpha: 0.28),
                        ),
                      ),
                      child: Text(
                        initiative.isActive ? 'ACTIVE' : 'INACTIVE',
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: initiative.isActive
                              ? colors.success
                              : colors.danger,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (initiative.description.isNotEmpty) ...[
              const SizedBox(height: CoolSpace.x1),
              Text(
                initiative.description,
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colors.secondaryText,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: CoolSpace.x2),
            Semantics(
              label:
                  'Progress ${(progress * 100).round()} percent.'
                  '$fmtRaised raised of $fmtTarget Rwandan francs target.',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: colors.cardSurface,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    initiative.isActive ? colors.success : colors.info,
                  ),
                  minHeight: 8,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InitiativeInfoPill(
                  label: 'Raised',
                  value: '$fmtRaised / $fmtTarget RWF',
                ),
                _InitiativeInfoPill(
                  label: 'Supporters',
                  value: '${initiative.supporterCount}',
                ),
                _InitiativeInfoPill(label: 'Ends', value: endsStr),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Btn(
                  icon: initiative.isActive ? Icons.pause : Icons.play_arrow,
                  label: initiative.isActive ? 'Deactivate' : 'Activate',
                  onTap: onToggleActive,
                ),
                _Btn(icon: Icons.edit, label: 'Edit', onTap: onEdit),
                _Btn(
                  icon: Icons.people_outline_rounded,
                  label: 'Supporters',
                  onTap: onViewContributors,
                ),
                _Btn(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  onTap: onDelete,
                  color: colors.danger,
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
  const _Btn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final resolvedColor = color ?? colors.secondaryText;
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
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colors.cardSurfaceStrong,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: colors.borderStrong),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: resolvedColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: resolvedColor,
                ),
              ),
            ],
          ),
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
    final colors = context.coolSemanticColors;
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
          style: GoogleFonts.dmSans(
            color: colors.primaryText,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: GoogleFonts.dmSans(
              color: colors.tertiaryText,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            filled: true,
            fillColor: colors.inputSurface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: RsColors.rsBlue),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 16,
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
    final colors = context.coolSemanticColors;
    final contributionsAsync = ref.watch(
      rsAdminInitiativeContributionsProvider(initiative.id),
    );
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
                color: colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          Text(
            initiative.title,
            style: context.coolText.rayonCondensed(
              const TextStyle(fontSize: 28),
              fontWeight: FontWeight.w900,
              color: colors.primaryText,
              height: 0.95,
            ),
          ),
          const SizedBox(height: CoolSpace.x1),
          Text(
            '${initiative.supporterCount} supporters · ${moneyFmt.format(initiative.raisedAmount)} RWF raised',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x4),
          Text(
            'Recent Contributions',
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Expanded(
            child: contributionsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Failed to load contributions',
                  style: GoogleFonts.dmSans(color: colors.tertiaryText),
                ),
              ),
              data: (contributions) {
                if (contributions.isEmpty) {
                  final colors = context.coolSemanticColors;
                  return Center(
                    child: Text(
                      'No contributions yet',
                      style: GoogleFonts.dmSans(color: colors.tertiaryText),
                    ),
                  );
                }
                return ListView.separated(
                  controller: scrollController,
                  itemCount: contributions.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final colors = context.coolSemanticColors;
                    final c = contributions[index];
                    final dateStr = DateFormat(
                      'd MMM, HH:mm',
                    ).format(c.createdAt);
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
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: colors.primaryText,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  dateStr,
                                  style: GoogleFonts.dmSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: colors.tertiaryText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${moneyFmt.format(c.amount)} RWF',
                            style: GoogleFonts.dmSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: colors.success,
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

String _title(String value) => '${value[0].toUpperCase()}${value.substring(1)}';

class _InitiativeFilterChip extends StatelessWidget {
  const _InitiativeFilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? RsColors.rsBlue.withValues(alpha: 0.18)
              : colors.chipBackground,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected ? RsColors.rsBlue : colors.border,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: isSelected ? RsColors.rsBlueLight : colors.secondaryText,
          ),
        ),
      ),
    );
  }
}

class _InitiativeInfoPill extends StatelessWidget {
  const _InitiativeInfoPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        '$label: $value',
        style: GoogleFonts.dmSans(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: colors.secondaryText,
        ),
      ),
    );
  }
}