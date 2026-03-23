import '../../../../core/theme/rs_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/cool_foundations.dart';
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
import '../../../../core/l10n/l10n.dart';
import '../../../../shared/widgets/cool_bottom_sheet.dart';

part '../widgets/rs_admin_finance_parts.dart';

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
    final colors = context.coolSemanticColors;
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

    await showCoolBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.elevatedBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final colors = context.coolSemanticColors;
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
                        color: colors.border,
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
                      color: colors.primaryText,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: countryController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Country'),
                  ),
                  const SizedBox(height: CoolSpace.x3),
                  TextField(
                    controller: providerController,
                    decoration: const InputDecoration(labelText: 'Provider'),
                  ),
                  const SizedBox(height: CoolSpace.x3),
                  TextField(
                    controller: recipientController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Recipient code',
                    ),
                  ),
                  const SizedBox(height: CoolSpace.x3),
                  TextField(
                    controller: labelController,
                    decoration: const InputDecoration(
                      labelText: 'Reconciliation label',
                    ),
                  ),
                  const SizedBox(height: CoolSpace.x3),
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
        title: Text(context.l10n.deletePaymentRoute),
        content: Text('Remove the ${route.countryCode} payment?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.delete),
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
    final colors = context.coolSemanticColors;
    final partnerIdAsync = ref.watch(rayonPartnerIdProvider);
    return partnerIdAsync.when(
      loading: () => Scaffold(
        backgroundColor: colors.appBackground,
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Scaffold(
        backgroundColor: colors.appBackground,
        body: Center(child: Text(context.l10n.financeWorkspaceCouldNot)),
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
          subtitle: 'Manage Rayon payment routing',
          metrics: [
            RsAdminMetric(label: 'routes', value: '$routeCount'),
            RsAdminMetric(label: 'active', value: '$activeRouteCount'),
            RsAdminMetric(label: 'ledger entries', value: '$ledgerCount'),
          ],
          child: ListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
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
              const SizedBox(height: CoolSpace.x4),
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
