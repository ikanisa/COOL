import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/cool_async_view.dart';
import '../../../../shared/widgets/cool_empty_view.dart';
import '../../../../shared/widgets/cool_skeleton.dart';
import '../../providers/rayon_sports_provider.dart';
import '../models/rs_models.dart';
import '../providers/rs_admin_provider.dart';
import '../widgets/rs_admin_shell.dart';

/// Admin screen for managing shop orders — all orders, status pipeline,
/// detail bottom sheet, status filter.
class RsAdminOrdersScreen extends ConsumerStatefulWidget {
  const RsAdminOrdersScreen({super.key});

  static const _statusFlow = [
    'pending',
    'confirmed',
    'shipped',
    'delivered',
    'cancelled',
  ];

  @override
  ConsumerState<RsAdminOrdersScreen> createState() =>
      _RsAdminOrdersScreenState();
}

class _RsAdminOrdersScreenState extends ConsumerState<RsAdminOrdersScreen> {
  String _statusFilter = 'all';

  static const _filters = ['all', 'pending', 'confirmed', 'shipped', 'delivered', 'cancelled'];

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(rsAdminOrdersProvider);

    return RsAdminShell(
      title: 'Shop Orders',
      subtitle: 'Manage fulfilment queue and track order status.',
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
                    .where((o) => o.status != OrderStatus.cancelled)
                    .fold<int>(0, (sum, o) => sum + o.total);
                  return '${NumberFormat.decimalPattern('en_US').format(total)} RWF';
                },
              ) ??
              '...',
        ),
      ],
      controls: SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _filters.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final f = _filters[index];
            final active = f == _statusFilter;
            return FilterChip(
              label: Text(f == 'all' ? 'All' : f[0].toUpperCase() + f.substring(1)),
              selected: active,
              onSelected: (_) => setState(() => _statusFilter = f),
              backgroundColor: AppColors.surface,
              selectedColor: AppColors.rsBlue.withValues(alpha: 0.15),
              labelStyle: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? AppColors.rsBlue : AppColors.text2,
              ),
            );
          },
        ),
      ),
      child: CoolAsyncView<List<RsShopOrder>>(
        value: ordersAsync,
        onRetry: () => ref.invalidate(rsAdminOrdersProvider),
        loadingWidget: const Padding(
          padding: EdgeInsets.all(16),
          child: CoolSkeletonList(itemCount: 4),
        ),
        emptyCheck: (orders) => orders.isEmpty,
        emptyWidget: const CoolEmptyView(
          subtitle: 'No shop orders yet',
          icon: Icons.shopping_bag_outlined,
          isPremium: true,
        ),
        builder: (orders) {
          final filtered = _statusFilter == 'all'
              ? orders
              : orders.where((o) => o.status.value == _statusFilter).toList();
          if (filtered.isEmpty) {
            return const CoolEmptyView(
              subtitle: 'No orders match this filter',
              icon: Icons.filter_list_off_rounded,
              isPremium: true,
            );
          }
          return ListView.separated(
            padding: EdgeInsets.zero,
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
    final dateStr = DateFormat('d MMM yyyy, HH:mm').format(order.createdAt);
    final moneyFmt = NumberFormat.decimalPattern('en_US');

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
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
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Order #${order.id.substring(0, 8).toUpperCase()}',
              style: GoogleFonts.dmSans(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            _DetailRow(label: 'Status', value: order.status.value.toUpperCase()),
            _DetailRow(label: 'Date', value: dateStr),
            _DetailRow(label: 'Total', value: '${moneyFmt.format(order.total)} RWF'),
            if (order.deliveryAddress.isNotEmpty)
              _DetailRow(label: 'Address', value: order.deliveryAddress),
            if (order.momoReference.isNotEmpty)
              _DetailRow(label: 'MoMo Ref', value: order.momoReference),
            const SizedBox(height: 16),
            Text(
              'Items (${order.items.length})',
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            ...order.items.map((item) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Text(item.product.imageEmoji.isNotEmpty ? item.product.imageEmoji : '📦',
                      style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.product.name,
                          style: GoogleFonts.dmSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                        Text(
                          '${item.quantity}x · ${moneyFmt.format(item.product.price)} RWF each',
                          style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.text3),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${moneyFmt.format(item.quantity * item.product.price)} RWF',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 16),
            Text(
              'Update Status',
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: RsAdminOrdersScreen._statusFlow
                  .where((s) => s != order.status.value)
                  .map(
                    (s) => OutlinedButton(
                      onPressed: () async {
                        final repo = ref.read(rayonSportsRepositoryProvider);
                        await repo.updateOrderStatus(order.id, status: s);
                        ref.invalidate(rsAdminOrdersProvider);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: Text('→ ${s[0].toUpperCase()}${s.substring(1)}'),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.text3,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
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
    final dateStr = DateFormat('d MMM HH:mm').format(order.createdAt);
    final itemCount = order.items.length;
    final moneyFmt = NumberFormat.decimalPattern('en_US');

    return RepaintBoundary(
      child: GestureDetector(
      onTap: onTap,
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
                    '#${order.id.substring(0, 8).toUpperCase()} · $itemCount items',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ),
                _StatusBadge(status: order.status.value),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${moneyFmt.format(order.total)} RWF · $dateStr',
              style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.text3),
            ),
            if (order.deliveryAddress.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                '📍 ${order.deliveryAddress}',
                style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.text3),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: RsAdminOrdersScreen._statusFlow
                  .where((s) => s != order.status.value)
                  .take(3)
                  .map(
                    (s) => GestureDetector(
                      onTap: () => onStatusChange(s),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '→ $s',
                          style: GoogleFonts.dmSans(
                            fontSize: 11,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  Color get _color => switch (status) {
    'confirmed' => AppColors.blue,
    'shipped' => AppColors.purple,
    'delivered' => AppColors.accent,
    'cancelled' => AppColors.red,
    _ => AppColors.yellow,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.toUpperCase(),
        style: GoogleFonts.dmSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: _color,
        ),
      ),
    );
  }
}
