import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/providers/referral_providers.dart';
import '../../../../core/status/cool_status_awarder.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_text_field.dart';
import '../../rayon/models/rs_models.dart';
import '../../rayon/rayon_payment.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../widgets/rayon_screen_scaffold.dart';
import '../../widgets/rayon_state_views.dart';

class ShopCheckoutScreen extends ConsumerStatefulWidget {
  const ShopCheckoutScreen({
    this.referralParameters = const <String, String>{},
    super.key,
  });

  final Map<String, String> referralParameters;

  @override
  ConsumerState<ShopCheckoutScreen> createState() => _ShopCheckoutScreenState();
}

class _ShopCheckoutScreenState extends ConsumerState<ShopCheckoutScreen>
    with CoolStatusAwarder {
  final _addressController = TextEditingController();
  String? _openedOrderId;
  int? _openedOrderTotal;
  String? _openedMessage;

  String? get _referralInviteId {
    final fromRoute = widget.referralParameters['ri']?.trim();
    if (fromRoute != null && fromRoute.isNotEmpty) {
      return fromRoute;
    }

    return ref.read(activeReferralAttributionProvider)?.inviteId;
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shopCatalog = ref.watch(rayonShopCatalogProvider);
    final notifier = ref.read(rayonSportsProvider.notifier);
    final ordersAsync = _openedOrderId == null
        ? const AsyncData<List<RsShopOrder>>(<RsShopOrder>[])
        : ref.watch(rayonShopOrdersProvider);
    final openedOrder = _findOrderById(ordersAsync.valueOrNull, _openedOrderId);

    return RayonScreenScaffold(
      title: _openedOrderId == null
          ? 'Checkout'
          : _checkoutTitle(openedOrder?.status ?? OrderStatus.pending),
      scrollable: false,
      child: shopCatalog.when(
        data: (shop) {
          if (_openedOrderId != null) {
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
                  sliver: SliverToBoxAdapter(
                    child: _CheckoutStatusState(
                      orderId: _openedOrderId!,
                      total: _openedOrderTotal ?? 0,
                      orderAsync: ordersAsync,
                      order: openedOrder,
                      message: _openedMessage ?? 'Shop checkout opened.',
                      onRefreshStatus: () =>
                          ref.invalidate(rayonShopOrdersProvider),
                      onBackToShop: () =>
                          context.go('/partners/rayon-sports/shop'),
                      onViewOrders: () =>
                          context.go('/partners/rayon-sports/profile'),
                    ),
                  ),
                ),
              ],
            );
          }

          final products = shop.selectedProducts();

          if (products.isEmpty) {
            return _EmptyCheckout(
              onBackToShop: () => context.go('/partners/rayon-sports/shop'),
            );
          }

          final hasMemberDiscount = shop.hasMemberDiscount;
          final subtotal = shop.subtotalFor(products);
          final discountAmount = shop.discountFor(subtotal);
          const delivery = 0;
          final total = subtotal - discountAmount + delivery;

          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Text(
                      'Your order',
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppColors.rsWhite,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ]),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final product = products[index];
                    final qty = shop.quantityFor(product.id);
                    final lineTotal = product.price * qty;
                    final discountedTotal = hasMemberDiscount
                        ? (lineTotal * 0.9).round()
                        : lineTotal;

                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == products.length - 1 ? 0 : 10,
                      ),
                      child: CoolCard(
                        gradient: AppColors.cardGradient,
                        borderColor: RsColors.rsBlueBorder,
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.surface3,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                product.imageEmoji,
                                style: const TextStyle(fontSize: 22),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    product.name,
                                    style: GoogleFonts.barlow(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.text,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Qty $qty',
                                    style: GoogleFonts.dmSans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.text2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              _fmtRwf(discountedTotal),
                              style: GoogleFonts.dmMono(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.text,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }, childCount: products.length),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 96),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    CoolCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Delivery or pickup',
                            style: GoogleFonts.barlow(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 12),
                          CoolTextField(
                            controller: _addressController,
                            label: 'Address',
                            hint: 'Pickup at Kigali Pele Stadium',
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    CoolCard(
                      child: Column(
                        children: [
                          _SummaryRow(
                            label: 'Subtotal',
                            value: _fmtRwf(subtotal),
                          ),
                          if (discountAmount > 0)
                            _SummaryRow(
                              label: 'Member discount',
                              value: '-${_fmtRwf(discountAmount)}',
                              valueColor: AppColors.accent,
                            ),
                          const _SummaryRow(label: 'Delivery', value: 'Free'),
                          const Divider(color: AppColors.border),
                          _SummaryRow(
                            label: 'Total',
                            value: _fmtRwf(total),
                            valueColor: AppColors.rsWhite,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    CoolButton(
                      label: 'Pay ${_fmtRwf(total)} via MTN MoMo',
                      onTap: () async {
                        try {
                          final referralInviteId = _referralInviteId;
                          final result = await notifier.checkoutShop(
                            products: products,
                            membership: shop.membership,
                            quantities: shop.cart,
                            deliveryAddress:
                                _addressController.text.trim().isEmpty
                                ? 'Pickup at Kigali Pele Stadium'
                                : _addressController.text.trim(),
                            referralInviteId: referralInviteId,
                          );
                          if (!context.mounted) {
                            return;
                          }
                          setState(() {
                            _openedOrderId = result.orderId;
                            _openedOrderTotal = result.total;
                            _openedMessage = result.message;
                          });
                          if (referralInviteId != null &&
                              referralInviteId.isNotEmpty) {
                            ref
                                .read(
                                  activeReferralAttributionProvider.notifier,
                                )
                                .clearIfMatches(referralInviteId);
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(result.message)),
                          );
                        } catch (error) {
                          if (!context.mounted) {
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(error.toString())),
                          );
                        }
                      },
                      icon: Icons.phone_in_talk_outlined,
                    ),
                  ]),
                ),
              ),
            ],
          );
        },
        loading: RayonLoadingView.new,
        error: (error, _) =>
            RayonErrorView(message: error.toString(), onRetry: notifier.load),
      ),
    );
  }

  static String _fmtRwf(int amount) {
    return '${NumberFormat.decimalPattern('en').format(amount)} RWF';
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.barlow(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.text2,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.dmMono(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: valueColor ?? AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckoutStatusState extends StatelessWidget {
  const _CheckoutStatusState({
    required this.orderId,
    required this.total,
    required this.orderAsync,
    required this.order,
    required this.message,
    required this.onRefreshStatus,
    required this.onBackToShop,
    required this.onViewOrders,
  });

  final String orderId;
  final int total;
  final AsyncValue<List<RsShopOrder>> orderAsync;
  final RsShopOrder? order;
  final String message;
  final VoidCallback onRefreshStatus;
  final VoidCallback onBackToShop;
  final VoidCallback onViewOrders;

  @override
  Widget build(BuildContext context) {
    final status = order?.status ?? OrderStatus.pending;
    final color = _statusColor(status);

    return Center(
      child: Column(
        children: [
          const SizedBox(height: 36),
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.16),
              border: Border.all(
                color: color.withValues(alpha: 0.42),
                width: 2,
              ),
            ),
            alignment: Alignment.center,
            child: Icon(_statusIcon(status), size: 38, color: color),
          ),
          const SizedBox(height: 18),
          Text(
            _statusHeadline(status),
            style: GoogleFonts.barlowCondensed(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: AppColors.rsWhite,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _statusBody(status, total, message),
            textAlign: TextAlign.center,
            style: GoogleFonts.barlow(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          CoolCard(
            child: orderAsync.when(
              data: (_) =>
                  _OrderSummary(order: order, fallbackOrderId: orderId),
              loading: () => _OrderSummaryLoading(orderId: orderId),
              error: (error, _) => _OrderSummaryError(
                orderId: orderId,
                onRefreshStatus: onRefreshStatus,
              ),
            ),
          ),
          const SizedBox(height: 18),
          CoolButton(
            label: 'Refresh order status',
            variant: CoolButtonVariant.secondary,
            onTap: onRefreshStatus,
            icon: Icons.sync_rounded,
          ),
          const SizedBox(height: 10),
          CoolButton(label: 'Back to shop', onTap: onBackToShop),
          const SizedBox(height: 10),
          CoolButton(
            label: 'View profile orders',
            variant: CoolButtonVariant.secondary,
            onTap: onViewOrders,
          ),
        ],
      ),
    );
  }
}

class _OrderSummary extends StatelessWidget {
  const _OrderSummary({required this.order, required this.fallbackOrderId});

  final RsShopOrder? order;
  final String fallbackOrderId;

  @override
  Widget build(BuildContext context) {
    final orderValue = order;
    if (orderValue == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Order record is still syncing.',
            style: GoogleFonts.barlow(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.rsWhite,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Order ID $fallbackOrderId was created, but the latest backend state is still loading.',
            style: GoogleFonts.barlow(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.4,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Order ${orderValue.status.label.toUpperCase()}',
                style: GoogleFonts.barlow(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.rsWhite,
                ),
              ),
            ),
            _OrderStatusChip(status: orderValue.status),
          ],
        ),
        const SizedBox(height: 12),
        _SummaryRow(label: 'Order ID', value: orderValue.id),
        _SummaryRow(
          label: 'Amount',
          value: _ShopCheckoutScreenState._fmtRwf(orderValue.total),
          valueColor: AppColors.rsWhite,
        ),
        _SummaryRow(label: 'MoMo ref', value: orderValue.momoReference),
        _SummaryRow(label: 'Delivery', value: orderValue.deliveryAddress),
        _SummaryRow(
          label: 'Created',
          value: DateFormat('dd MMM, HH:mm').format(orderValue.createdAt),
        ),
        if (orderValue.status == OrderStatus.pending) ...[
          const SizedBox(height: 6),
          Text(
            'Fulfillment starts only after MTN MoMo confirms this order.',
            style: GoogleFonts.barlow(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: RsColors.rsGoldLight,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

class _OrderSummaryLoading extends StatelessWidget {
  const _OrderSummaryLoading({required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Checking backend order state...',
          style: GoogleFonts.barlow(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.rsWhite,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Order ID $orderId has been created. We are loading its latest payment status.',
          style: GoogleFonts.barlow(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.text2,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _OrderSummaryError extends StatelessWidget {
  const _OrderSummaryError({
    required this.orderId,
    required this.onRefreshStatus,
  });

  final String orderId;
  final VoidCallback onRefreshStatus;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Order status unavailable',
          style: GoogleFonts.barlow(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.rsWhite,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Order ID $orderId exists, but the latest backend status could not be loaded yet.',
          style: GoogleFonts.barlow(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.text2,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: onRefreshStatus,
          icon: const Icon(Icons.sync_rounded, size: 18),
          label: const Text('Try again'),
        ),
      ],
    );
  }
}

class _OrderStatusChip extends StatelessWidget {
  const _OrderStatusChip({required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        status.label.toUpperCase(),
        style: GoogleFonts.barlow(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _EmptyCheckout extends StatelessWidget {
  const _EmptyCheckout({required this.onBackToShop});

  final VoidCallback onBackToShop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80),
      child: Center(
        child: Column(
          children: [
            const Icon(
              Icons.shopping_cart_outlined,
              size: 56,
              color: AppColors.text3,
            ),
            const SizedBox(height: 16),
            Text(
              'Your cart is empty',
              style: GoogleFonts.barlowCondensed(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.rsWhite,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add products from the Rayon shop before starting checkout.',
              textAlign: TextAlign.center,
              style: GoogleFonts.barlow(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.text2,
              ),
            ),
            const SizedBox(height: 18),
            CoolButton(label: 'Back to shop', onTap: onBackToShop),
          ],
        ),
      ),
    );
  }
}

RsShopOrder? _findOrderById(List<RsShopOrder>? orders, String? orderId) {
  if (orders == null || orderId == null || orderId.isEmpty) {
    return null;
  }

  for (final order in orders) {
    if (order.id == orderId) {
      return order;
    }
  }

  return null;
}

String _checkoutTitle(OrderStatus status) {
  return switch (status) {
    OrderStatus.pending => 'Order Pending',
    OrderStatus.confirmed => 'Order Confirmed',
    OrderStatus.shipped => 'Order Shipped',
    OrderStatus.delivered => 'Order Delivered',
    OrderStatus.cancelled => 'Order Cancelled',
  };
}

Color _statusColor(OrderStatus status) {
  return switch (status) {
    OrderStatus.pending => RsColors.rsGoldLight,
    OrderStatus.confirmed => AppColors.accent,
    OrderStatus.shipped => RsColors.rsBluePale,
    OrderStatus.delivered => AppColors.rsWhite,
    OrderStatus.cancelled => AppColors.text3,
  };
}

IconData _statusIcon(OrderStatus status) {
  return switch (status) {
    OrderStatus.pending => Icons.schedule_rounded,
    OrderStatus.confirmed => Icons.check_circle_outline_rounded,
    OrderStatus.shipped => Icons.local_shipping_outlined,
    OrderStatus.delivered => Icons.inventory_2_outlined,
    OrderStatus.cancelled => Icons.block_outlined,
  };
}

String _statusHeadline(OrderStatus status) {
  return switch (status) {
    OrderStatus.pending => 'Waiting for Payment Confirmation',
    OrderStatus.confirmed => 'Order Confirmed',
    OrderStatus.shipped => 'Order on the Way',
    OrderStatus.delivered => 'Order Delivered',
    OrderStatus.cancelled => 'Order Cancelled',
  };
}

String _statusBody(OrderStatus status, int total, String openedMessage) {
  return switch (status) {
    OrderStatus.pending =>
      '$openedMessage We launched ${rayonSportsMomoUssd(total)}. Approve the MTN MoMo payment to move this Rayon Sports order from pending to confirmed.',
    OrderStatus.confirmed =>
      'MTN MoMo confirmation has arrived. Your Rayon Sports order is now in the fulfillment queue.',
    OrderStatus.shipped =>
      'This order has been confirmed and handed over for delivery.',
    OrderStatus.delivered =>
      'This Rayon Sports order has been marked as delivered.',
    OrderStatus.cancelled =>
      'This order is no longer active. If you completed payment, refresh the status or contact support.',
  };
}
