import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/cool_foundations.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/cool_toast.dart';
import '../../models/group_contribution.dart';
import '../../providers/groups_provider.dart';
import 'group_detail_helpers.dart';

// ═════════════════════════════════════════════════════════════════════════
// Contribution row (used in the detail screen list)
// ═════════════════════════════════════════════════════════════════════════

class GroupContributionRow extends StatelessWidget {
  const GroupContributionRow({required this.contribution, super.key});

  final GroupContribution contribution;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final dateLabel = contribution.createdAt != null
        ? DateFormat('d MMM y').format(contribution.createdAt!)
        : '';
    final contributorLabel =
        contribution.contributorName?.trim().isNotEmpty == true
        ? contribution.contributorName!.trim()
        : '#${contribution.userId.substring(0, contribution.userId.length < 8 ? contribution.userId.length : 8)}';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: CoolSpace.x4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.financialSurface,
              borderRadius: const BorderRadius.all(
                Radius.circular(CoolRadii.sm),
              ),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.download_rounded, size: 20, color: colors.accent),
          ),
          const SizedBox(width: CoolSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$contributorLabel contributed',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
                const SizedBox(height: CoolSpace.x1),
                Text(
                  dateLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '+${groupFormatAmount(contribution.amount)} RWF',
            style: text.mono(
              theme.textTheme.titleMedium,
              fontWeight: FontWeight.w800,
              color: colors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Contribute bottom sheet
// ═════════════════════════════════════════════════════════════════════════

class GroupContributeSheet extends ConsumerStatefulWidget {
  const GroupContributeSheet({
    required this.groupId,
    required this.groupName,
    required this.monthlyAmount,
    required this.frequency,
    this.onSuccess,
    super.key,
  });

  final String groupId;
  final String groupName;
  final int monthlyAmount;
  final String frequency;
  final void Function(String groupId)? onSuccess;

  @override
  ConsumerState<GroupContributeSheet> createState() =>
      _GroupContributeSheetState();
}

class _GroupContributeSheetState extends ConsumerState<GroupContributeSheet> {
  late final TextEditingController _amountController;
  int? _selectedMultiplier;

  @override
  void initState() {
    super.initState();
    ref.read(groupsProvider.notifier).clearContributionState();
    _amountController = TextEditingController(
      text: widget.monthlyAmount.toString(),
    );
    _selectedMultiplier = 1;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _selectAmount(int multiplierIndex) {
    final amounts = [
      widget.monthlyAmount ~/ 2,
      widget.monthlyAmount,
      widget.monthlyAmount * 2,
    ];
    setState(() {
      _selectedMultiplier = multiplierIndex;
      _amountController.text = amounts[multiplierIndex].toString();
    });
  }

  Future<void> _payViaMomo() async {
    final amount = int.tryParse(
      _amountController.text.replaceAll(',', '').trim(),
    );
    if (amount == null || amount <= 0) {
      CoolToast.error(context, 'Enter a valid contribution amount.');
      return;
    }

    final success = await ref
        .read(groupsProvider.notifier)
        .contribute(widget.groupId, amount);

    if (!mounted) return;

    if (success) {
      CoolToast.success(
        context,
        'MoMo payment initiated. Your contribution will appear '
        'once the payment is confirmed via SMS.',
      );
      widget.onSuccess?.call(widget.groupId);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final theme = Theme.of(context);
    final isLoading = ref.watch(groupContributionLoadingProvider);
    final error = ref.watch(groupContributionErrorProvider);
    final half = widget.monthlyAmount ~/ 2;
    final full = widget.monthlyAmount;
    final doubleAmount = widget.monthlyAmount * 2;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.borderStrong,
                  borderRadius: BorderRadius.all(Radius.circular(radii.xs)),
                ),
              ),
            ),
            SizedBox(height: space.x5),
            Text(
              widget.groupName,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.primaryText,
              ),
            ),
            SizedBox(height: space.x1),
            Text(
              '${groupFormatFrequency(widget.frequency)} contribution • '
              'RWF ${groupFormatAmount(full)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.secondaryText,
                height: 1.4,
              ),
            ),
            SizedBox(height: space.x5),
            Text(
              'Amount',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.secondaryText,
              ),
            ),
            SizedBox(height: space.x2),
            Semantics(
              textField: true,
              label: 'Contribution amount in Rwandan francs',
              hint: 'Enter amount',
              child: TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                style: text.mono(
                  theme.textTheme.headlineSmall,
                  fontWeight: FontWeight.w800,
                  color: colors.accent,
                ),
                cursorColor: colors.accent,
                decoration: InputDecoration(
                  prefixText: 'RWF ',
                  prefixStyle: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.tertiaryText,
                  ),
                  filled: true,
                  fillColor: colors.inputSurface,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: space.x4,
                    vertical: space.x4,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(radii.sm)),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(radii.sm)),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(radii.sm)),
                    borderSide: BorderSide(color: colors.accent, width: 1.5),
                  ),
                ),
                onChanged: (_) => setState(() => _selectedMultiplier = null),
              ),
            ),
            SizedBox(height: space.x3),
            Wrap(
              spacing: space.x2,
              runSpacing: space.x2,
              children: [
                _AmountChip(
                  label: 'Half (${_formatK(half)})',
                  isSelected: _selectedMultiplier == 0,
                  onTap: () => _selectAmount(0),
                ),
                _AmountChip(
                  label: 'Full (${_formatK(full)})',
                  isSelected: _selectedMultiplier == 1,
                  onTap: () => _selectAmount(1),
                ),
                _AmountChip(
                  label: 'Double (${_formatK(doubleAmount)})',
                  isSelected: _selectedMultiplier == 2,
                  onTap: () => _selectAmount(2),
                ),
              ],
            ),
            SizedBox(height: space.x5),
            CoolButton(
              label: 'Pay via MOMO',
              icon: Icons.phone_android_rounded,
              isLoading: isLoading,
              onTap: _payViaMomo,
            ),
            if (error != null) ...[
              SizedBox(height: space.x3),
              Text(
                error,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.danger,
                ),
              ),
            ],
            SizedBox(height: space.x3),
            Container(
              padding: EdgeInsets.all(space.x3),
              decoration: BoxDecoration(
                color: colors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.all(Radius.circular(radii.sm)),
                border: Border.all(
                  color: colors.warning.withValues(alpha: 0.28),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.phone_rounded, size: 16, color: colors.warning),
                  SizedBox(width: space.x2),
                  Expanded(
                    child: Text(
                      'You will confirm the contribution on your MoMo prompt.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.secondaryText,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatK(int value) {
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}K';
    }
    return value.toString();
  }
}

class _AmountChip extends StatelessWidget {
  const _AmountChip({
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
    final radii = context.coolRadii;
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      selected: isSelected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.all(Radius.circular(radii.pill)),
          onTap: onTap,
          child: AnimatedContainer(
            duration: CoolMotion.quick,
            curve: CoolMotion.enterCurve,
            constraints: const BoxConstraints(
              minWidth: 112,
              minHeight: CoolTapTargets.minimum,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: CoolSpace.x4,
              vertical: CoolSpace.x3,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? colors.chipSelectedBackground
                  : colors.chipBackground,
              borderRadius: BorderRadius.all(Radius.circular(radii.pill)),
              border: Border.all(
                color: isSelected ? colors.accent : colors.border,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: isSelected ? colors.accent : colors.secondaryText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
