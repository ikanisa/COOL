import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../shared/widgets/cool_async_view.dart';
import '../../../../shared/widgets/cool_bottom_sheet.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_empty_view.dart';
import '../../../../shared/widgets/cool_skeleton.dart';
import '../../providers/rayon_sports_provider.dart';
import '../models/rs_models.dart';
import '../providers/rs_admin_provider.dart';
import '../widgets/rs_admin_shell.dart';

/// Admin screen for managing shop orders.
class RsAdminOrdersScreen extends ConsumerStatefulWidget {
  const RsAdminOrdersScreen({super.key});

  static const _statusFlow = <String>[
    'pending',
    'paid',
    'confirmed',
    'packed',
    'shipped',
    'fulfilled',
    'delivered',
    'cancelled',
  ];

  @override
  ConsumerState<RsAdminOrdersScreen> createState() =>
      _RsAdminOrdersScreenState();
}

class _RsAdminOrdersScreenState extends ConsumerState<RsAdminOrdersScreen> {
  String _statusFilter = 'all';

  static const _filters = <String>[
    'all',
    'pending',
    'paid',
    'confirmed',
    'packed',
    'shipped',
    'fulfilled',
    'delivered',
    'cancelled',
  ];

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(rsAdminOrdersProvider);

    return RsAdminShell(
      title: 'Shop Orders',
      subtitle:
          'Control payment confirmation, fulfilment movement, and delivery exceptions from one command queue.',
      metrics: [
        RsAdminMetric(
          label: 'orders',
          value:
              ordersAsync.whenOrNull(data: (orders) => '${orders.length}') ??
              '...',
        ),
        RsAdminMetric(
          label: 'pending',
          value:
              ordersAsync.whenOrNull(
                data: (orders) =>
                    '${orders.where((order) => order.status == OrderStatus.pending).length}',
              ) ??
              '...',
        ),
        RsAdminMetric(
          label: 'revenue',
          value:
              ordersAsync.whenOrNull(
                data: (orders) {
                  final total = orders
                      .where((order) => order.status != OrderStatus.cancelled)
                      .fold<int>(0, (sum, order) => sum + order.total);
                  return '${NumberFormat.decimalPattern('en_US').format(total)} RWF';
                },
              ) ??
              '...',
        ),
      ],
      controls: SizedBox(
        height: 44,
        child:
            ordersAsync.whenOrNull(
              data: (orders) {
                final counts = <String, int>{};
                for (final order in orders) {
                  final status = order.status.name;
                  counts[status] = (counts[status] ?? 0) + 1;
                }
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _filters.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final filter = _filters[index];
                    final count = filter == 'all'
                        ? orders.length
                        : (counts[filter] ?? 0);
                    return _OrderFilterChip(
                      label: '${_title(filter)} ($count)',
                      isSelected: filter == _statusFilter,
                      onTap: () => setState(() => _statusFilter = filter),
                    );
                  },
                );
              },
            ) ??
            const SizedBox.shrink(),
      ),
      child: CoolAsyncView<List<RsShopOrder>>(
        value: ordersAsync,
        onRetry: () => ref.invalidate(rsAdminOrdersProvider),
        loadingWidget: const Padding(
          padding: EdgeInsets.all(16),
          child: CoolSkeletonList(itemCount: 4),
        ),
        emptyCheck: (orders) => orders.isEmpty,
        emptyWidget: CoolEmptyView(
          subtitle: context.l10n.rsAdminNoOrders,
          icon: Icons.shopping_bag_outlined,
          isPremium: true,
        ),
        builder: (orders) {
          final filtered = _statusFilter == 'all'
              ? orders
              : orders
                    .where((order) => order.status.value == _statusFilter)
                    .toList();
          if (filtered.isEmpty) {
            return const CoolEmptyView(
              subtitle: 'No orders match this filter',
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
              final order = filtered[index];
              return _OrderTile(
                order: order,
                onStatusChange: (status) async {
                  final repo = ref.read(rayonSportsRepositoryProvider);
                  await repo.updateOrderStatus(order.id, status: status);
                  ref.invalidate(rsAdminOrdersProvider);
                },
                onTap: () => _showOrderDetail(order),
              );
            },
          );
        },
      ),
    );
  }

  void _showOrderDetail(RsShopOrder order) {
    final colors = context.coolSemanticColors;
    final dateStr = DateFormat('d MMM yyyy, HH:mm').format(order.createdAt);
    final moneyFmt = NumberFormat.decimalPattern('en_US');

    showCoolBottomSheet(
      context: context,
      backgroundColor: colors.overlaySurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            _OrderDetailCommandCard(
              order: order,
              dateStr: dateStr,
              moneyFmt: moneyFmt,
            ),
            const SizedBox(height: 20),
            Text(
              context.l10n.rsAdminItemsCount(order.items.length),
              style: GoogleFonts.dmSans(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: colors.primaryText,
              ),
            ),
            const SizedBox(height: 10),
            ...order.items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: CoolCard(
                  backgroundColor: colors.commerceSurface,
                  borderColor: colors.border,
                  child: Row(
                    children: [
                      Text(
                        item.product.imageEmoji.isNotEmpty
                            ? item.product.imageEmoji
                            : '📦',
                        style: const TextStyle(fontSize: 28),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.product.name,
                              style: GoogleFonts.dmSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: colors.primaryText,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${item.quantity}x  •  ${moneyFmt.format(item.product.price)} RWF each',
                              style: GoogleFonts.dmSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: colors.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${moneyFmt.format(item.quantity * item.product.price)} RWF',
                        style: GoogleFonts.dmSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: colors.primaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Move Order',
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: colors.primaryText,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: RsAdminOrdersScreen._statusFlow
                  .where((status) => status != order.status.value)
                  .map(
                    (status) => _OrderActionPill(
                      label: 'Move to ${_title(status)}',
                      onTap: () async {
                        final repo = ref.read(rayonSportsRepositoryProvider);
                        await repo.updateOrderStatus(order.id, status: status);
                        ref.invalidate(rsAdminOrdersProvider);
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                        }
                      },
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

String _title(String value) => '${value[0].toUpperCase()}${value.substring(1)}';

Color _orderStatusColor(BuildContext context, String status) {
  final colors = context.coolSemanticColors;
  return switch (status) {
    'paid' => colors.success,
    'confirmed' => colors.info,
    'packed' || 'shipped' => AppColors.rsBlueLight,
    'fulfilled' || 'delivered' => colors.accent,
    'cancelled' => colors.danger,
    _ => colors.warning,
  };
}

class _OrderFilterChip extends StatelessWidget {
  const _OrderFilterChip({
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
              ? AppColors.rsBlue.withValues(alpha: 0.18)
              : colors.chipBackground,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected ? AppColors.rsBlue : colors.border,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: isSelected ? AppColors.rsBlueLight : colors.secondaryText,
          ),
        ),
      ),
    );
  }
}

class _OrderDetailCommandCard extends StatelessWidget {
  const _OrderDetailCommandCard({
    required this.order,
    required this.dateStr,
    required this.moneyFmt,
  });

  final RsShopOrder order;
  final String dateStr;
  final NumberFormat moneyFmt;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

    return CoolCard(
      backgroundColor: colors.cardSurfaceStrong,
      borderColor: _orderStatusColor(
        context,
        order.status.value,
      ).withValues(alpha: 0.34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Official Fulfilment Order',
            style: GoogleFonts.barlow(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.rsAdminOrderNumber(
              order.id.substring(0, 8).toUpperCase(),
            ),
            style: GoogleFonts.barlowCondensed(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: colors.primaryText,
              height: 0.96,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusBadge(status: order.status.value),
              _OrderValuePill(
                label: 'Total',
                value: '${moneyFmt.format(order.total)} RWF',
              ),
              _OrderValuePill(label: 'Created', value: dateStr),
            ],
          ),
          const SizedBox(height: 14),
          if (order.deliveryAddress.isNotEmpty)
            _DetailRow(label: 'Delivery', value: order.deliveryAddress),
          if (order.momoReference.isNotEmpty)
            _DetailRow(label: 'MoMo Ref', value: order.momoReference),
          _DetailRow(
            label: 'Items',
            value:
                '${order.items.length} line${order.items.length == 1 ? '' : 's'}',
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: colors.tertiaryText,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: colors.primaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({
    required this.order,
    required this.onStatusChange,
    required this.onTap,
  });

  final RsShopOrder order;
  final void Function(String status) onStatusChange;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final dateStr = DateFormat('d MMM HH:mm').format(order.createdAt);
    final moneyFmt = NumberFormat.decimalPattern('en_US');

    return RepaintBoundary(
      child: CoolCard(
        onTap: onTap,
        backgroundColor: colors.commerceSurface,
        borderColor: _orderStatusColor(
          context,
          order.status.value,
        ).withValues(alpha: 0.28),
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
                        '#${order.id.substring(0, 8).toUpperCase()}',
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: colors.primaryText,
                          height: 0.95,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${order.items.length} items  •  ${moneyFmt.format(order.total)} RWF',
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: colors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusBadge(status: order.status.value),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _OrderValuePill(label: 'Created', value: dateStr),
                if (order.deliveryAddress.isNotEmpty)
                  _OrderValuePill(label: 'Route', value: order.deliveryAddress),
              ],
            ),
            if (order.deliveryAddress.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Delivery: ${order.deliveryAddress}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors.tertiaryText,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: RsAdminOrdersScreen._statusFlow
                  .where((status) => status != order.status.value)
                  .take(3)
                  .map(
                    (status) => _OrderActionPill(
                      label: 'Move to ${_title(status)}',
                      onTap: () => onStatusChange(status),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _orderStatusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        status.toUpperCase(),
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _OrderValuePill extends StatelessWidget {
  const _OrderValuePill({required this.label, required this.value});

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
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.dmSans(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: colors.secondaryText,
        ),
      ),
    );
  }
}

class _OrderActionPill extends StatelessWidget {
  const _OrderActionPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colors.cardSurfaceStrong,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.borderStrong),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppColors.rsBlueLight,
          ),
        ),
      ),
    );
  }
}
