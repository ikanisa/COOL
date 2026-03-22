import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/l10n/l10n.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../momo/services/momo_statement_export_service.dart';
import '../models/group_contribution.dart';
import '../models/group_member.dart';
import '../providers/group_ledger_provider.dart';
import '../providers/groups_provider.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';

/// Period presets for the group ledger filter.
enum _LedgerPeriod { week, month, year, all }

/// Full-page screen showing all contributions for a group,
/// with filters by contributor and period, plus export.
class GroupLedgerScreen extends ConsumerStatefulWidget {
  const GroupLedgerScreen({required this.groupId, super.key});
  final String groupId;

  @override
  ConsumerState<GroupLedgerScreen> createState() => _GroupLedgerScreenState();
}

class _GroupLedgerScreenState extends ConsumerState<GroupLedgerScreen> {

  _LedgerPeriod _selectedPeriod = _LedgerPeriod.all;
  String? _selectedContributorId;

  // ── Derived dates ──────────────────────────────────────────
  DateTime? get _startDate {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case _LedgerPeriod.week:
        return now.subtract(const Duration(days: 7));
      case _LedgerPeriod.month:
        return DateTime(now.year, now.month - 1, now.day);
      case _LedgerPeriod.year:
        return DateTime(now.year - 1, now.month, now.day);
      case _LedgerPeriod.all:
        return null;
    }
  }

  GroupLedgerQuery get _query => GroupLedgerQuery(
        groupId: widget.groupId,
        contributorId: _selectedContributorId,
        startDate: _startDate,
      );

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final detailAsync = ref.watch(groupDetailProvider(widget.groupId));
    final ledgerAsync = ref.watch(groupLedgerProvider(_query));
    final groupName =
        detailAsync.valueOrNull?.group.name ?? context.l10n.group;
    final members = detailAsync.valueOrNull?.members ?? const <GroupMember>[];

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              groupName,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
               context.l10n.ledgerTitle,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: palette.text3),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: palette.accent,
        onPressed: () => _showExportSheet(context, ledgerAsync, groupName),
        icon: const Icon(Icons.download_rounded, color: Colors.white),
        label: Text(
           context.l10n.exportAction,
          style: GoogleFonts.dmSans(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: CoolScreenBackground(
        primaryColor: palette.accent,
        secondaryColor: palette.blue,
        child: Column(
          children: [
            // ── Filters ──
            _FiltersBar(
              selectedPeriod: _selectedPeriod,
              selectedContributorId: _selectedContributorId,
              members: members,
              onPeriodChanged: (p) => setState(() => _selectedPeriod = p),
              onContributorChanged: (id) =>
                  setState(() => _selectedContributorId = id),
            ),

            // ── Summary card ──
            ledgerAsync.whenOrNull(
                  data: (entries) => _SummaryCard(entries: entries),
                ) ??
                const SizedBox.shrink(),

            // ── Transactions list ──
            Expanded(
              child: CoolAsyncView<List<GroupContribution>>(
                value: ledgerAsync,
                onRetry: () => ref.invalidate(groupLedgerProvider(_query)),
                loadingWidget: const Padding(
                  padding: EdgeInsets.all(18),
                  child: CoolSkeletonList(itemCount: 6),
                ),
                emptyCheck: (entries) => entries.isEmpty,
                emptyWidget: CoolEmptyView(
                  message: context.l10n.noContributionsForFilter,
                ),
                builder: (entries) => ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 96),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) =>
                      _ContributionTile(entry: entries[index]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Export ──────────────────────────────────────────────────
  Future<void> _showExportSheet(
    BuildContext context,
    AsyncValue<List<GroupContribution>> ledgerAsync,
    String groupName,
  ) async {
    final palette = context.coolPalette;
    final entries = ledgerAsync.valueOrNull;
    if (entries == null || entries.isEmpty) {
      CoolToast.info(context, context.l10n.noDataToExport);
      return;
    }

    // Cache l10n values before async gap.
    final l10n = context.l10n;
    final periodLabel = switch (_selectedPeriod) {
      _LedgerPeriod.week => l10n.last7Days,
      _LedgerPeriod.month => l10n.lastMonth,
      _LedgerPeriod.year => l10n.lastYear,
      _LedgerPeriod.all => l10n.allTime,
    };
    final contributorLabel = _selectedContributorId == null
        ? l10n.allContributors
        : entries.firstWhere(
            (e) => e.userId == _selectedContributorId,
            orElse: () => entries.first,
          ).contributorName ?? l10n.filteredContributor;
    final sortLabelCached = l10n.newestFirst;

    final format = await showCoolBottomSheet<StatementExportFormat>(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ExportFormatSheet(),
    );

    if (format == null || !mounted) return;

    try {
      final exportService = MomoStatementExportService();
      final result = await exportService.buildGroupLedgerExport(
        format: format,
        entries: entries,
        metadata: StatementExportMetadata(
          statementTitle: '$groupName — Group Ledger',
          fileStem: 'cool_group_ledger',
          userName: groupName,
          officialPhone: '',
          generatedAt: DateTime.now(),
          periodLabel: periodLabel,
          filterLabel: contributorLabel,
          sortLabel: sortLabelCached,
        ),
      );

      if (!mounted) return;

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(result.bytes, mimeType: result.mimeType, name: result.fileName)],
        ),
      );

      if (mounted) {
        CoolToast.success(context, l10n.ledgerExported(result.fileName));
      }
    } catch (e) {
      if (mounted) {
        CoolToast.error(context, l10n.exportFailed);
      }
    }
  }
}

// ═════════════════════════════════════════════════════════════
// FILTERS BAR
// ═════════════════════════════════════════════════════════════
class _FiltersBar extends StatelessWidget {
  const _FiltersBar({
    required this.selectedPeriod,
    required this.selectedContributorId,
    required this.members,
    required this.onPeriodChanged,
    required this.onContributorChanged,
  });

  final _LedgerPeriod selectedPeriod;
  final String? selectedContributorId;
  final List<GroupMember> members;
  final ValueChanged<_LedgerPeriod> onPeriodChanged;
  final ValueChanged<String?> onContributorChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Period chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _LedgerPeriod.values.map((p) {
                final isSelected = p == selectedPeriod;
                final label = switch (p) {
                  _LedgerPeriod.week => context.l10n.week,
                  _LedgerPeriod.month => context.l10n.month,
                  _LedgerPeriod.year => context.l10n.year,
                  _LedgerPeriod.all => context.l10n.allTime,
                };
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: isSelected,
                    selectedColor: palette.accent,
                    backgroundColor: palette.surface2,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : palette.text2,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    side: BorderSide.none,
                    onSelected: (_) => onPeriodChanged(p),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          // Contributor dropdown
          if (members.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: palette.surface2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: selectedContributorId,
                  isExpanded: true,
                  icon: Icon(Icons.keyboard_arrow_down_rounded,
                      color: palette.text3),
                  dropdownColor: palette.surface,
                  style: GoogleFonts.dmSans(
                    color: palette.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  hint: Text(
                    context.l10n.allContributors,
                    style: GoogleFonts.dmSans(
                      color: palette.text3,
                      fontSize: 14,
                    ),
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(context.l10n.allContributors),
                    ),
                    ...members.map((m) => DropdownMenuItem<String?>(
                          value: m.userId,
                          child: Text(
                            m.displayName ?? m.userId.substring(0, 8),
                            overflow: TextOverflow.ellipsis,
                          ),
                        )),
                  ],
                  onChanged: onContributorChanged,
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════
// SUMMARY CARD
// ═════════════════════════════════════════════════════════════
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.entries});
  final List<GroupContribution> entries;

  static final _amountFmt = NumberFormat.decimalPattern('en_US');

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final total = entries.fold<int>(0, (sum, e) => sum + e.amount);
    final contributors =
        entries.map((e) => e.userId).toSet().length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      child: CoolCard(
        gradient: AppColors.cardGradient,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Expanded(
                child: _MetricColumn(
                  label: context.l10n.total,
                  value: 'RWF ${_amountFmt.format(total)}',
                  color: palette.accent,
                ),
              ),
              Container(
                width: 1,
                height: 36,
                color: palette.surface3,
              ),
              Expanded(
                child: _MetricColumn(
                  label: context.l10n.contributorsLabel,
                  value: contributors.toString(),
                  color: palette.blue,
                ),
              ),
              Container(
                width: 1,
                height: 36,
                color: palette.surface3,
              ),
              Expanded(
                child: _MetricColumn(
                  label: context.l10n.entries,
                  value: entries.length.toString(),
                  color: palette.purple,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricColumn extends StatelessWidget {
  const _MetricColumn({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Column(
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: GoogleFonts.dmMono(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: palette.text3),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════
// CONTRIBUTION TILE
// ═════════════════════════════════════════════════════════════
class _ContributionTile extends StatelessWidget {
  const _ContributionTile({required this.entry});
  final GroupContribution entry;

  static final _dateFmt = DateFormat('dd MMM yyyy, HH:mm');
  static final _amountFmt = NumberFormat.decimalPattern('en_US');

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final statusColor = switch (entry.status) {
      'confirmed' || 'completed' => palette.accent,
      'pending' => Colors.amber,
      'failed' => Colors.redAccent,
      _ => palette.text3,
    };

    return CoolCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 20,
              backgroundColor: palette.surface3,
              child: Text(
                (entry.contributorName ?? '?')[0].toUpperCase(),
                style: GoogleFonts.dmSans(
                  color: palette.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.contributorName ?? 'Unknown',
                    style: GoogleFonts.dmSans(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: palette.text,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    entry.createdAt != null
                        ? _dateFmt.format(entry.createdAt!)
                        : '-',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: palette.text3, fontSize: 12),
                  ),
                ],
              ),
            ),
            // Amount + status
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'RWF ${_amountFmt.format(entry.amount)}',
                  style: GoogleFonts.dmMono(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: 3),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _titleize(entry.status),
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _titleize(String raw) {
    if (raw.trim().isEmpty) return '-';
    return raw
        .split('_')
        .where((p) => p.isNotEmpty)
        .map((p) => '${p[0].toUpperCase()}${p.substring(1)}')
        .join(' ');
  }
}

// ═════════════════════════════════════════════════════════════
// EXPORT FORMAT SHEET
// ═════════════════════════════════════════════════════════════
class _ExportFormatSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.exportLedger,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.chooseExportFormat,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: palette.text3),
            ),
            const SizedBox(height: 20),
            _ExportOption(
              icon: Icons.picture_as_pdf_rounded,
              label: 'PDF',
              subtitle: context.l10n.printReadyStatement,
              color: Colors.redAccent,
              onTap: () =>
                  Navigator.pop(context, StatementExportFormat.pdf),
            ),
            const SizedBox(height: 10),
            _ExportOption(
              icon: Icons.table_chart_rounded,
              label: 'Excel',
              subtitle: context.l10n.spreadsheetHeaders,
              color: Colors.green,
              onTap: () =>
                  Navigator.pop(context, StatementExportFormat.excel),
            ),
            const SizedBox(height: 10),
            _ExportOption(
              icon: Icons.text_snippet_rounded,
              label: 'CSV',
              subtitle: context.l10n.plainTextData,
              color: palette.blue,
              onTap: () =>
                  Navigator.pop(context, StatementExportFormat.csv),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportOption extends StatelessWidget {
  const _ExportOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Material(
      color: palette.surface2,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: palette.text,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: palette.text3),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: palette.text3),
            ],
          ),
        ),
      ),
    );
  }
}
