import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/cool_async_view.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_empty_view.dart';
import '../../../../shared/widgets/cool_toast.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../momo/models/momo_statement.dart';
import '../../../momo/providers/momo_statement_providers.dart';
import '../../../momo/services/momo_statement_export_service.dart';
import '../../../partners/providers/rayon_sports_provider.dart';
import '../providers/rs_admin_provider.dart';
import '../rayon_payment.dart';
import '../widgets/rs_admin_shell.dart';

class RsAdminFinanceScreen extends ConsumerStatefulWidget {
  const RsAdminFinanceScreen({super.key});

  @override
  ConsumerState<RsAdminFinanceScreen> createState() =>
      _RsAdminFinanceScreenState();
}

class _RsAdminFinanceScreenState extends ConsumerState<RsAdminFinanceScreen> {
  bool _isExporting = false;
  bool _isSavingRoute = false;
  String? _deletingRouteId;

  PartnerPaymentRoute? _activeRoute(List<PartnerPaymentRoute> routes) {
    for (final route in routes) {
      if (route.isActive) {
        return route;
      }
    }
    return routes.isEmpty ? null : routes.first;
  }

  Future<void> _exportLedger({
    required StatementExportFormat format,
    required String partnerId,
    required String partnerName,
    required List<PayeePaymentLedgerEntry> entries,
  }) async {
    if (_isExporting || entries.isEmpty) {
      return;
    }

    setState(() => _isExporting = true);
    try {
      final authState = ref.read(authProvider);
      final exportService = ref.read(momoStatementExportServiceProvider);
      final downloadService = ref.read(momoStatementDownloadServiceProvider);
      final export = await exportService.buildPayeeLedgerExport(
        format: format,
        entries: entries,
        metadata: StatementExportMetadata(
          statementTitle: '$partnerName partner ledger',
          fileStem: 'rayon_finance_$partnerId',
          userName: authState.user?.fullName.trim().isNotEmpty == true
              ? authState.user!.fullName.trim()
              : partnerName,
          officialPhone:
              authState.user?.officialPhone ?? authState.user?.phone ?? '',
          generatedAt: DateTime.now(),
          periodLabel: 'Latest posted partner receipts',
          filterLabel: 'Partner payment ledger',
          sortLabel: 'Newest first',
        ),
      );
      final result = await downloadService.saveExport(export);
      if (!mounted) {
        return;
      }
      CoolToast.success(context, 'Ledger exported to ${result.fileName}.');
    } catch (_) {
      if (!mounted) {
        return;
      }
      CoolToast.error(
        context,
        'Could not export the partner ledger right now.',
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _openRouteEditor({PartnerPaymentRoute? route}) async {
    if (_isSavingRoute) {
      return;
    }

    final countryController = TextEditingController(
      text: route?.countryCode ?? 'RW',
    );
    final providerController = TextEditingController(
      text: route?.providerId ?? 'mtn_rwanda',
    );
    final recipientController = TextEditingController(
      text: route?.recipientCode ?? '',
    );
    final labelController = TextEditingController(
      text: route?.reconciliationLabel ?? 'rayon_sports',
    );
    var selectedStatus = route?.status ?? PartnerPaymentRouteStatus.active;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    route == null ? 'New payment route' : 'Edit payment route',
                    style: GoogleFonts.dmSans(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: countryController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Country'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: providerController,
                    decoration: const InputDecoration(labelText: 'Provider'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: recipientController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Recipient code',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: labelController,
                    decoration: const InputDecoration(
                      labelText: 'Reconciliation label',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<PartnerPaymentRouteStatus>(
                    initialValue: selectedStatus,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: PartnerPaymentRouteStatus.values
                        .map(
                          (status) => DropdownMenuItem(
                            value: status,
                            child: Text(_title(status.name)),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setModalState(() => selectedStatus = value);
                    },
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isSavingRoute
                          ? null
                          : () async {
                              final countryCode = countryController.text
                                  .trim()
                                  .toUpperCase();
                              final providerId = providerController.text.trim();
                              final recipientCode = recipientController.text
                                  .trim();
                              final reconciliationLabel = labelController.text
                                  .trim();
                              if (countryCode.isEmpty ||
                                  providerId.isEmpty ||
                                  recipientCode.isEmpty ||
                                  reconciliationLabel.isEmpty) {
                                CoolToast.error(
                                  context,
                                  'All payment route fields are required.',
                                );
                                return;
                              }

                              Navigator.of(context).pop();
                              setState(() => _isSavingRoute = true);
                              try {
                                final repository = ref.read(
                                  rayonSportsRepositoryProvider,
                                );
                                await repository.upsertPaymentRoute(
                                  countryCode: countryCode,
                                  providerId: providerId,
                                  recipientCode: recipientCode,
                                  reconciliationLabel: reconciliationLabel,
                                  status: selectedStatus,
                                );
                                ref.invalidate(rsAdminPaymentRoutesProvider);
                                ref.invalidate(rayonPaymentRouteProvider);
                                if (!mounted) {
                                  return;
                                }
                                CoolToast.success(
                                  this.context,
                                  'Payment route saved.',
                                );
                              } catch (_) {
                                if (!mounted) {
                                  return;
                                }
                                CoolToast.error(
                                  this.context,
                                  'Could not save this payment route.',
                                );
                              } finally {
                                if (mounted) {
                                  setState(() => _isSavingRoute = false);
                                }
                              }
                            },
                      child: Text(
                        route == null ? 'Create route' : 'Save route',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _deleteRoute(PartnerPaymentRoute route) async {
    if (_deletingRouteId != null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete payment route'),
        content: Text(
          'Remove the ${route.countryCode} payment?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() => _deletingRouteId = route.id);
    try {
      final repository = ref.read(rayonSportsRepositoryProvider);
      await repository.deletePaymentRoute(route.id);
      ref.invalidate(rsAdminPaymentRoutesProvider);
      ref.invalidate(rayonPaymentRouteProvider);
      if (!mounted) {
        return;
      }
      CoolToast.success(context, 'Payment route deleted.');
    } catch (_) {
      if (!mounted) {
        return;
      }
      CoolToast.error(context, 'Could not delete this payment route.');
    } finally {
      if (mounted) {
        setState(() => _deletingRouteId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final partnerIdAsync = ref.watch(rayonPartnerIdProvider);
    return partnerIdAsync.when(
      loading: () => Scaffold(
        backgroundColor: AppColors.bg,
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Scaffold(
        backgroundColor: AppColors.bg,
        body: const Center(
          child: Text('Finance workspace could not'),
        ),
      ),
      data: (partnerId) {
        final routesAsync = ref.watch(rsAdminPaymentRoutesProvider);
        final ledgerAsync = partnerId.trim().isEmpty
            ? const AsyncValue.data(
                MomoStatementPage<PayeePaymentLedgerEntry>(),
              )
            : ref.watch(
                partnerPaymentLedgerProvider(
                  PartnerPaymentLedgerQuery(
                    partnerId: partnerId,
                    statementQuery: const MomoStatementQuery(limit: 100),
                  ),
                ),
              );
        final routeCount =
            routesAsync.whenOrNull(data: (routes) => routes.length) ?? 0;
        final activeRouteCount =
            routesAsync.whenOrNull(
              data: (routes) => routes.where((route) => route.isActive).length,
            ) ??
            0;
        final activeRoute = _activeRoute(routesAsync.valueOrNull ?? const []);
        final ledgerCount =
            ledgerAsync.whenOrNull(data: (page) => page.entries.length) ?? 0;
        final partnerName = activeRoute?.partnerName ?? 'Rayon Sports';

        return RsAdminShell(
          title: 'Finance',
          subtitle:
              'Manage Rayon payment routing',
          metrics: [
            RsAdminMetric(label: 'routes', value: '$routeCount'),
            RsAdminMetric(label: 'active', value: '$activeRouteCount'),
            RsAdminMetric(label: 'ledger entries', value: '$ledgerCount'),
          ],
          child: ListView(
            children: [
              _RouteCardList(
                routesAsync: routesAsync,
                activeRouteId: activeRoute?.id,
                isSavingRoute: _isSavingRoute,
                deletingRouteId: _deletingRouteId,
                onCreateRoute: () => _openRouteEditor(),
                onEditRoute: (route) => _openRouteEditor(route: route),
                onDeleteRoute: _deleteRoute,
              ),
              const SizedBox(height: 16),
              _PartnerLedgerCard(
                ledgerAsync: ledgerAsync,
                onRetry: partnerId.trim().isEmpty
                    ? null
                    : () => ref.invalidate(
                        partnerPaymentLedgerProvider(
                          PartnerPaymentLedgerQuery(
                            partnerId: partnerId,
                            statementQuery: const MomoStatementQuery(
                              limit: 100,
                            ),
                          ),
                        ),
                      ),
                isExporting: _isExporting,
                onExport: (format, entries) => _exportLedger(
                  format: format,
                  partnerId: partnerId,
                  partnerName: partnerName,
                  entries: entries,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RouteCardList extends StatelessWidget {
  const _RouteCardList({
    required this.routesAsync,
    required this.activeRouteId,
    required this.isSavingRoute,
    required this.deletingRouteId,
    required this.onCreateRoute,
    required this.onEditRoute,
    required this.onDeleteRoute,
  });

  final AsyncValue<List<PartnerPaymentRoute>> routesAsync;
  final String? activeRouteId;
  final bool isSavingRoute;
  final String? deletingRouteId;
  final VoidCallback onCreateRoute;
  final ValueChanged<PartnerPaymentRoute> onEditRoute;
  final ValueChanged<PartnerPaymentRoute> onDeleteRoute;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      borderColor: AppColors.border2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Payment routing',
                      style: GoogleFonts.barlow(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.rsWhite,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Partner-admin managed recipient codes',
                      style: GoogleFonts.barlow(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text2,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: isSavingRoute ? null : onCreateRoute,
                child: const Text('New route'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          CoolAsyncView<List<PartnerPaymentRoute>>(
            value: routesAsync,
            emptyCheck: (routes) => routes.isEmpty,
            emptyWidget: const CoolEmptyView(
              subtitle: 'No partner payment yet',
              compact: true,
              isPremium: true,
            ),
            builder: (routes) => Column(
              children: routes
                  .map(
                    (route) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _RouteRow(
                        route: route,
                        isActiveRoute: route.id == activeRouteId,
                        isDeleting: deletingRouteId == route.id,
                        onEdit: () => onEditRoute(route),
                        onDelete: () => onDeleteRoute(route),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({
    required this.route,
    required this.isActiveRoute,
    required this.isDeleting,
    required this.onEdit,
    required this.onDelete,
  });

  final PartnerPaymentRoute route;
  final bool isActiveRoute;
  final bool isDeleting;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (route.status) {
      PartnerPaymentRouteStatus.active => AppColors.accent,
      PartnerPaymentRouteStatus.inactive => AppColors.orange,
      PartnerPaymentRouteStatus.draft => AppColors.text3,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActiveRoute ? AppColors.rsBlueBorder : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${route.countryCode} · ${route.providerLabel}',
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ),
              _StatusPill(label: _title(route.status.name), color: statusColor),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            route.payToLabel,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.text2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Label: ${route.reconciliationLabel}',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.text3,
            ),
          ),
          if (route.ussdPattern.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'USSD: ${route.ussdPattern}',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.text3,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton(onPressed: onEdit, child: const Text('Edit')),
              TextButton(
                onPressed: isDeleting ? null : onDelete,
                child: Text(isDeleting ? 'Deleting...' : 'Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PartnerLedgerCard extends StatelessWidget {
  const _PartnerLedgerCard({
    required this.ledgerAsync,
    required this.onRetry,
    required this.isExporting,
    required this.onExport,
  });

  final AsyncValue<MomoStatementPage<PayeePaymentLedgerEntry>> ledgerAsync;
  final VoidCallback? onRetry;
  final bool isExporting;
  final Future<void> Function(
    StatementExportFormat format,
    List<PayeePaymentLedgerEntry> entries,
  ) onExport;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      borderColor: AppColors.border2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Posted partner ledger',
            style: GoogleFonts.barlow(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.rsWhite,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Latest posted partner receipts',
            style: GoogleFonts.barlow(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          CoolAsyncView<MomoStatementPage<PayeePaymentLedgerEntry>>(
            value: ledgerAsync,
            onRetry: onRetry,
            emptyCheck: (page) => page.entries.isEmpty,
            emptyWidget: const CoolEmptyView(
              subtitle: 'No posted partner yet',
              compact: true,
              isPremium: true,
            ),
            builder: (page) => Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton.icon(
                        onPressed: isExporting
                            ? null
                            : () => onExport(StatementExportFormat.pdf, page.entries),
                        icon: isExporting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.picture_as_pdf_outlined),
                        label: Text(isExporting ? 'Exporting...' : 'Export PDF'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: isExporting
                            ? null
                            : () => onExport(StatementExportFormat.excel, page.entries),
                        icon: isExporting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.table_view_rounded),
                        label: Text(isExporting ? 'Exporting...' : 'Export Excel'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ...page.entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _LedgerRow(entry: entry),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.entry});

  final PayeePaymentLedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.decimalPattern('en_US');
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    return Container(
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
                  entry.payerName,
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ),
              Text(
                '${money.format(entry.amount)} ${entry.currency}',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            dateFormat.format(entry.occurredAt),
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _LedgerPill(label: 'Category', value: _title(entry.txCategory)),
              _LedgerPill(label: 'Bucket', value: _title(entry.cashflowBucket)),
              _LedgerPill(label: 'Target', value: _title(entry.targetTable)),
              _LedgerPill(
                label: 'Reference',
                value: entry.reference?.trim().isNotEmpty == true
                    ? entry.reference!
                    : '-',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LedgerPill extends StatelessWidget {
  const _LedgerPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        '$label: $value',
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

String _title(String value) {
  final normalized = value.replaceAll('_', ' ').trim();
  if (normalized.isEmpty) {
    return '-';
  }
  return normalized
      .split(RegExp(r'\s+'))
      .map((part) {
        if (part.isEmpty) {
          return part;
        }
        return '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
      })
      .join(' ');
}
