part of '../screens/rs_admin_finance_screen.dart';

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
    final palette = context.coolPalette;
    return CoolCard(
      borderColor: palette.border2,
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
                        color: palette.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Partner-admin managed recipient codes',
                      style: GoogleFonts.barlow(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: palette.text2,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: isSavingRoute ? null : onCreateRoute,
                child: Text(context.l10n.newRoute),
              ),
            ],
          ),
          const SizedBox(height: 14),
          CoolAsyncView<List<PartnerPaymentRoute>>(
            value: routesAsync,
            emptyCheck: (routes) => routes.isEmpty,
            emptyWidget: const CoolEmptyView(
              message: 'No partner payment yet',
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
    final palette = context.coolPalette;
    final statusColor = switch (route.status) {
      PartnerPaymentRouteStatus.active => palette.accent,
      PartnerPaymentRouteStatus.inactive => palette.orange,
      PartnerPaymentRouteStatus.draft => palette.text3,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActiveRoute ? AppColors.rsBlueBorder : palette.border,
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
                    color: palette.text,
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
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: palette.text2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Label: ${route.reconciliationLabel}',
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: palette.text3,
            ),
          ),
          if (route.ussdPattern.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'USSD: ${route.ussdPattern}',
              style: GoogleFonts.dmSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: palette.text3,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton(onPressed: onEdit, child: Text(context.l10n.edit)),
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
  )
  onExport;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return CoolCard(
      borderColor: palette.border2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Posted partner ledger',
            style: GoogleFonts.barlow(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Latest posted partner receipts',
            style: GoogleFonts.barlow(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: palette.text2,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          CoolAsyncView<MomoStatementPage<PayeePaymentLedgerEntry>>(
            value: ledgerAsync,
            onRetry: onRetry,
            emptyCheck: (page) => page.entries.isEmpty,
            emptyWidget: const CoolEmptyView(
              message: 'No posted partner yet',
              compact: true,
              isPremium: true,
            ),
            builder: (page) => Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: OutlinedButton.icon(
                        onPressed: isExporting
                            ? null
                            : () => onExport(
                                StatementExportFormat.pdf,
                                page.entries,
                              ),
                        icon: isExporting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.picture_as_pdf_outlined),
                        label: Text(
                          isExporting ? 'Exporting...' : 'Export PDF',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: FilledButton.icon(
                        onPressed: isExporting
                            ? null
                            : () => onExport(
                                StatementExportFormat.excel,
                                page.entries,
                              ),
                        icon: isExporting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.table_view_rounded),
                        label: Text(
                          isExporting ? 'Exporting...' : 'Export Excel',
                        ),
                      ),
                    ),
                  ],
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
    final palette = context.coolPalette;
    final money = NumberFormat.decimalPattern('en_US');
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
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
                    color: palette.text,
                  ),
                ),
              ),
              Text(
                '${money.format(entry.amount)} ${entry.currency}',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: palette.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            dateFormat.format(entry.occurredAt),
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: palette.text2,
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
    final palette = context.coolPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        '$label: $value',
        style: GoogleFonts.dmSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: palette.text,
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
          fontSize: 14,
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
