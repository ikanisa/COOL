import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';
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

part 'group_ledger_screen_parts.dart';

enum _LedgerPeriod { week, month, year, all }

class GroupLedgerScreen extends ConsumerStatefulWidget {
  const GroupLedgerScreen({required this.groupId, super.key});

  final String groupId;

  @override
  ConsumerState<GroupLedgerScreen> createState() => _GroupLedgerScreenState();
}

class _GroupLedgerScreenState extends ConsumerState<GroupLedgerScreen> {
  _LedgerPeriod _selectedPeriod = _LedgerPeriod.all;
  String? _selectedContributorId;

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
    final colors = context.coolSemanticColors;
    final detailAsync = ref.watch(groupDetailProvider(widget.groupId));
    final ledgerAsync = ref.watch(groupLedgerProvider(_query));
    final groupName = detailAsync.valueOrNull?.group.name ?? context.l10n.group;
    final members = detailAsync.valueOrNull?.members ?? const <GroupMember>[];

    return Scaffold(
      backgroundColor: colors.appBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.primaryText),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              groupName,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.primaryText,
              ),
            ),
            Text(
              context.l10n.ledgerTitle,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.secondaryText),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: colors.buttonPrimaryBackground,
        onPressed: () => _showExportSheet(context, ledgerAsync, groupName),
        icon: Icon(Icons.download_rounded, color: colors.accentForeground),
        label: Text(
          context.l10n.exportAction,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: colors.accentForeground,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: CoolScreenBackground(
        primaryColor: colors.accent,
        secondaryColor: colors.info,
        child: Column(
          children: [
            _FiltersBar(
              selectedPeriod: _selectedPeriod,
              selectedContributorId: _selectedContributorId,
              members: members,
              onPeriodChanged: (period) =>
                  setState(() => _selectedPeriod = period),
              onContributorChanged: (id) =>
                  setState(() => _selectedContributorId = id),
            ),
            ledgerAsync.whenOrNull(
                  data: (entries) => _SummaryCard(entries: entries),
                ) ??
                const SizedBox.shrink(),
            Expanded(
              child: CoolAsyncView<List<GroupContribution>>(
                value: ledgerAsync,
                onRetry: () => ref.invalidate(groupLedgerProvider(_query)),
                loadingWidget: const Padding(
                  padding: EdgeInsets.all(CoolSpace.x4),
                  child: CoolSkeletonList(itemCount: 6),
                ),
                emptyCheck: (entries) => entries.isEmpty,
                emptyWidget: CoolEmptyView(
                  message: context.l10n.noContributionsForFilter,
                ),
                builder: (entries) => ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    CoolSpace.x4,
                    CoolSpace.x1,
                    CoolSpace.x4,
                    96,
                  ),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: CoolSpace.x2),
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

  Future<void> _showExportSheet(
    BuildContext context,
    AsyncValue<List<GroupContribution>> ledgerAsync,
    String groupName,
  ) async {
    final entries = ledgerAsync.valueOrNull;
    if (entries == null || entries.isEmpty) {
      CoolToast.info(context, context.l10n.noDataToExport);
      return;
    }

    final l10n = context.l10n;
    final periodLabel = switch (_selectedPeriod) {
      _LedgerPeriod.week => l10n.last7Days,
      _LedgerPeriod.month => l10n.lastMonth,
      _LedgerPeriod.year => l10n.lastYear,
      _LedgerPeriod.all => l10n.allTime,
    };
    final contributorLabel = _selectedContributorId == null
        ? l10n.allContributors
        : entries
                  .firstWhere(
                    (entry) => entry.userId == _selectedContributorId,
                    orElse: () => entries.first,
                  )
                  .contributorName ??
              l10n.filteredContributor;
    final sortLabelCached = l10n.newestFirst;

    final format = await showCoolBottomSheet<StatementExportFormat>(
      context: context,
      builder: (_) => const _ExportFormatSheet(),
    );

    if (format == null || !mounted) return;

    try {
      final exportService = MomoStatementExportService();
      final result = await exportService.buildGroupLedgerExport(
        format: format,
        entries: entries,
        metadata: StatementExportMetadata(
          statementTitle: '$groupName - Group Ledger',
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
          files: [
            XFile.fromData(
              result.bytes,
              mimeType: result.mimeType,
              name: result.fileName,
            ),
          ],
        ),
      );

      if (!context.mounted) return;
      CoolToast.success(context, l10n.ledgerExported(result.fileName));
    } catch (_) {
      if (!context.mounted) return;
      CoolToast.error(context, l10n.exportFailed);
    }
  }
}
