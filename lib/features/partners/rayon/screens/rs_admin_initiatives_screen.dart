import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/cool_async_view.dart';
import '../../../../shared/widgets/cool_empty_view.dart';
import '../../../../shared/widgets/cool_skeleton.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../widgets/partner_navigation.dart';
import '../models/rs_models.dart';
import '../providers/rs_admin_provider.dart';

/// Admin screen for managing RS initiatives — CRUD, toggle active, progress.
class RsAdminInitiativesScreen extends ConsumerStatefulWidget {
  const RsAdminInitiativesScreen({super.key});

  @override
  ConsumerState<RsAdminInitiativesScreen> createState() =>
      _RsAdminInitiativesScreenState();
}

class _RsAdminInitiativesScreenState
    extends ConsumerState<RsAdminInitiativesScreen> {
  @override
  Widget build(BuildContext context) {
    final initAsync = ref.watch(rsAdminInitiativesProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.rsBlue,
        elevation: 0,
        leading: buildPartnerBackButton(
          context,
          fallbackLocation: AppRoutes.adminRayon,
          color: Colors.white,
        ),
        title: Text(
          'Initiatives',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        actions: buildPartnerAppBarActions(context, homeColor: Colors.white),
      ),
      floatingActionButton: Semantics(
        button: true,
        label: 'Add initiative',
        hint: 'Opens the new initiative form',
        child: FloatingActionButton(
          backgroundColor: AppColors.rsBlue,
          onPressed: () => _showForm(context),
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
      body: CoolAsyncView<List<RsInitiative>>(
        value: initAsync,
        onRetry: () => ref.invalidate(rsAdminInitiativesProvider),
        loadingWidget: const Padding(
          padding: EdgeInsets.all(16),
          child: CoolSkeletonList(itemCount: 4),
        ),
        emptyCheck: (initiatives) => initiatives.isEmpty,
        emptyWidget: const CoolEmptyView(
          message: 'No initiatives have been created yet.',
          icon: Icons.flag_outlined,
        ),
        builder: (initiatives) => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: initiatives.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final init = initiatives[index];
            return _InitiativeTile(
              initiative: init,
              onToggleActive: () => _toggleActive(init),
              onEdit: () => _showForm(context, initiative: init),
            );
          },
        ),
      ),
    );
  }

  Future<void> _toggleActive(RsInitiative init) async {
    final repo = ref.read(rayonSportsRepositoryProvider);
    await repo.toggleInitiativeActive(init.id, isActive: !init.isActive);
    ref.invalidate(rsAdminInitiativesProvider);
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
  });
  final RsInitiative initiative;
  final VoidCallback onToggleActive;
  final VoidCallback onEdit;

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
          'Initiative ${initiative.title}. ${initiative.isActive ? 'Active' : 'Inactive'}. '
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
                  'Progress ${(progress * 100).round()} percent. '
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
              '$fmtRaised / $fmtTarget RWF · ${initiative.supporterCount} supporters · Ends $endsStr',
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      hint: 'Double tap to ${label.toLowerCase()} this initiative',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.text2),
            const SizedBox(width: 3),
            Text(
              label,
              style: GoogleFonts.dmSans(fontSize: 10, color: AppColors.text2),
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
        hint: 'Double tap to enter $label',
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
