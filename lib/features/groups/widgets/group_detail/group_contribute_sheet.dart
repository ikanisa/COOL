import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/cool_palette.dart';
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
    final palette = context.coolPalette;
    final dateLabel = contribution.createdAt != null
        ? DateFormat('d MMM y').format(contribution.createdAt!)
        : '';
    final contributorLabel =
        contribution.contributorName?.trim().isNotEmpty == true
        ? contribution.contributorName!.trim()
        : '#${contribution.userId.substring(0, 8.clamp(0, contribution.userId.length))}';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          // Green arrow icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.download_rounded,
              size: 20,
              color: palette.text2,
            ),
          ),
          const SizedBox(width: 14),

          // Name + date
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$contributorLabel contributed',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  dateLabel,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),

          // Amount
          Text(
            '+${groupFormatAmount(contribution.amount)} RWF',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: palette.accent,
              fontFamily: GoogleFonts.dmMono().fontFamily,
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
  int? _selectedMultiplier; // 0=half, 1=full, 2=double

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
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final isLoading = ref.watch(groupContributionLoadingProvider);
    final error = ref.watch(groupContributionErrorProvider);
    final half = widget.monthlyAmount ~/ 2;
    final full = widget.monthlyAmount;
    final double = widget.monthlyAmount * 2;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.border2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Group name + monthly
              Text(
                widget.groupName,
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: palette.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${groupFormatFrequency(widget.frequency)}:'
                'RWF ${groupFormatAmount(full)}',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: palette.text2,
                ),
              ),
              const SizedBox(height: 20),

              // Amount input
              Text(
                'Amount',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: palette.text2,
                ),
              ),
              const SizedBox(height: 8),
              Semantics(
                textField: true,
                label: 'Contribution amount in Rwandan',
                hint: 'Enter amount',
                child: TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  style: GoogleFonts.dmMono(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: palette.accent,
                  ),
                  cursorColor: palette.accent,
                  decoration: InputDecoration(
                    prefix: Text(
                      'RWF',
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: palette.text3,
                      ),
                    ),
                    filled: true,
                    fillColor: palette.surface2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: palette.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: palette.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: palette.accent,
                        width: 1.5,
                      ),
                    ),
                  ),
                  onChanged: (_) => setState(() => _selectedMultiplier = null),
                ),
              ),
              const SizedBox(height: 12),

              // Quick-select chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
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
                    label: 'Double (${_formatK(double)})',
                    isSelected: _selectedMultiplier == 2,
                    onTap: () => _selectAmount(2),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Pay button
              CoolButton(
                label: 'Pay via MOMO',
                icon: Icons.phone_android_rounded,
                isLoading: isLoading,
                onTap: _payViaMomo,
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: palette.red,
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // USSD banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: palette.yellow.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: palette.yellow.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.phone_rounded, size: 16, color: palette.text2),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You\'ll be redirected to',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: palette.yellow,
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

// ── Quick-select amount chip ────────────────────────────────────────────

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
    final palette = context.coolPalette;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? palette.accentGlow : palette.surface2,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: isSelected ? palette.accent : palette.border,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isSelected ? palette.accent : palette.text2,
            ),
          ),
        ),
      ),
    );
  }
}
