import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/cool_async_view.dart';
import '../../../../shared/widgets/cool_empty_view.dart';
import '../../../../shared/widgets/cool_skeleton.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../widgets/partner_navigation.dart';
import '../models/rs_models.dart';
import '../providers/rs_admin_provider.dart';

/// Admin screen for managing shop orders — all orders, status pipeline.
class RsAdminOrdersScreen extends ConsumerWidget {
  const RsAdminOrdersScreen({super.key});

  static const _statusFlow = [
    'pending',
    'confirmed',
    'shipped',
    'delivered',
    'cancelled',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(rsAdminOrdersProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.rsBlue,
        elevation: 0,
        leading: buildPartnerBackButton(
          context,
          fallbackLocation: AppRoutes.adminRayon,
          color: Colors.white,
        ),
        title: Text(
          'Shop Orders',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        actions: buildPartnerAppBarActions(context, homeColor: Colors.white),
      ),
      body: CoolAsyncView<List<RsShopOrder>>(
        value: ordersAsync,
        onRetry: () => ref.invalidate(rsAdminOrdersProvider),
        loadingWidget: const Padding(
          padding: EdgeInsets.all(16),
          child: CoolSkeletonList(itemCount: 4),
        ),
        emptyCheck: (orders) => orders.isEmpty,
        emptyWidget: const CoolEmptyView(
          message: 'No shop orders have been created yet.',
          icon: Icons.shopping_bag_outlined,
        ),
        builder: (orders) => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: orders.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final order = orders[index];
            return _OrderTile(
              order: order,
              onStatusChange: (status) async {
                final repo = ref.read(rayonSportsRepositoryProvider);
                await repo.updateOrderStatus(order.id, status: status);
                ref.invalidate(rsAdminOrdersProvider);
              },
            );
          },
        ),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order, required this.onStatusChange});
  final RsShopOrder order;
  final void Function(String status) onStatusChange;

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('d MMM HH:mm').format(order.createdAt);
    final itemCount = order.items.length;

    return Semantics(
      container: true,
      label:
          'Order ${order.id.substring(0, 8)}. $itemCount items. '
          'Total ${order.total} Rwandan francs. Created $dateStr. '
          'Status ${order.status.value}.'
          '${order.deliveryAddress.isNotEmpty ? ' Delivery address ${order.deliveryAddress}.' : ''}',
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
                    '#${order.id.substring(0, 8)} · $itemCount items',
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
              '${order.total} RWF · $dateStr',
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
                  .map(
                    (s) => Semantics(
                      button: true,
                      label: 'Change order status to $s',
                      hint: 'Double tap to mark this order as $s',
                      excludeSemantics: true,
                      child: GestureDetector(
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
    return Semantics(
      label: 'Status ${status.toLowerCase()}',
      child: ExcludeSemantics(
        child: Container(
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
        ),
      ),
    );
  }
}
