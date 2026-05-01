import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/money_formatters.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_toast.dart';

// ═══════════════════════════════════════════════════════════════
// Tab enum
// ═══════════════════════════════════════════════════════════════

/// Tabs available on the savings detail screen.
enum SavingsDetailTab {
  members('Members'),
  allocations('Allocations');

  const SavingsDetailTab(this.label);
  final String label;
}

// ═══════════════════════════════════════════════════════════════
// Group header card
// ═══════════════════════════════════════════════════════════════

/// Displays the group name, description, status, and key metrics.
class SavingsGroupHeaderCard extends StatelessWidget {
  const SavingsGroupHeaderCard({
    required this.name,
    required this.description,
    required this.targetAmount,
    required this.monthlyContribution,
    required this.totalCollected,
    required this.frequency,
    required this.inviteCode,
    required this.isClosed,
    required this.onCloseGroup,
    super.key,
  });

  final String name;
  final String? description;
  final int targetAmount;
  final int monthlyContribution;
  final int totalCollected;
  final String frequency;
  final String inviteCode;
  final bool isClosed;
  final VoidCallback? onCloseGroup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;

    return CoolCard(
      backgroundColor: colors.operationalSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.primaryText,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: (isClosed ? colors.danger : colors.success)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(CoolRadii.pill),
                ),
                child: Text(
                  isClosed
                      ? context.l10n.adminSavingsClosedStatus
                      : context.l10n.adminSavingsActiveStatus,
                  style: context.coolText.mono(
                    theme.textTheme.labelSmall,
                    fontWeight: FontWeight.w800,
                    color: isClosed ? colors.danger : colors.success,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          if (description != null && description!.isNotEmpty) ...[
            const SizedBox(height: CoolSpace.x2),
            Text(
              description!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.secondaryText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: CoolSpace.x4),
          Wrap(
            spacing: CoolSpace.x3,
            runSpacing: CoolSpace.x2,
            children: [
              SavingsInfoChip(
                label: '${formatWholeMoneyAmount(targetAmount)} target',
                icon: CoolIcons.flagFilled,
              ),
              SavingsInfoChip(
                label:
                    '${formatWholeMoneyAmount(monthlyContribution)} / mo',
                icon: CoolIcons.calendar,
              ),
              SavingsInfoChip(
                label:
                    '${formatWholeMoneyAmount(totalCollected)} collected',
                icon: CoolIcons.wallet,
              ),
              SavingsInfoChip(
                label: frequency.replaceAll('_', ' '),
                icon: CoolIcons.loop,
              ),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: inviteCode));
                  CoolToast.success(context, context.l10n.adminSavingsCopied);
                },
                child: SavingsInfoChip(
                  label: inviteCode,
                  icon: CoolIcons.qrCodeRounded,
                ),
              ),
            ],
          ),
          if (!isClosed) ...[
            const SizedBox(height: CoolSpace.x4),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onCloseGroup,
                icon: const Icon(CoolIcons.lock, size: 16),
                label: Text(context.l10n.adminSavingsCloseGroupButton),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.danger,
                  side: BorderSide(
                    color: colors.danger.withValues(alpha: 0.3),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(CoolRadii.sm),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Tab bar
// ═══════════════════════════════════════════════════════════════

/// Horizontal chip-based tab bar for [SavingsDetailTab].
class SavingsDetailTabBar extends StatelessWidget {
  const SavingsDetailTabBar({
    required this.activeTab,
    required this.onTabSelected,
    super.key,
  });

  final SavingsDetailTab activeTab;
  final ValueChanged<SavingsDetailTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final tab in SavingsDetailTab.values) ...[
            ChoiceChip(
              showCheckmark: false,
              label: Text(tab.label),
              selected: activeTab == tab,
              onSelected: (_) {
                HapticFeedback.selectionClick();
                onTabSelected(tab);
              },
              backgroundColor: colors.chipBackground,
              selectedColor: colors.chipSelectedBackground,
              labelStyle: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: activeTab == tab
                    ? colors.accentStrong
                    : colors.secondaryText,
              ),
              side: BorderSide.none,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(
                  Radius.circular(CoolRadii.pill),
                ),
              ),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Info chip
// ═══════════════════════════════════════════════════════════════

/// Small icon + label pair used for savings group metrics.
class SavingsInfoChip extends StatelessWidget {
  const SavingsInfoChip({required this.label, required this.icon, super.key});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colors.tertiaryText),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
            color: colors.tertiaryText,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Member row
// ═══════════════════════════════════════════════════════════════

const BorderRadius _chipRadius = BorderRadius.all(
  Radius.circular(CoolRadii.xs),
);

/// Single member row with avatar, name, phone, and remove button.
class SavingsMemberRow extends StatelessWidget {
  const SavingsMemberRow({
    required this.displayName,
    required this.phone,
    required this.onRemove,
    super.key,
  });

  final String displayName;
  final String? phone;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;

    return CoolCard(
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.info.withValues(alpha: 0.12),
              borderRadius: _chipRadius,
            ),
            child: Icon(CoolIcons.person, size: 18, color: colors.info),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
                if (phone != null)
                  Text(
                    phone!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colors.tertiaryText,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              CoolIcons.removeCircle,
              color: colors.danger,
              size: 20,
            ),
            tooltip: context.l10n.adminSavingsRemoveMemberTooltip,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
