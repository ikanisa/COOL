part of '../screens/shop_checkout_screen.dart';

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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: CoolSpace.x3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.secondaryText,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontFamily: GoogleFonts.dmMono().fontFamily,
              color: valueColor ?? colors.primaryText,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckoutCommandCard extends StatelessWidget {
  const _CheckoutCommandCard({
    required this.itemCount,
    required this.total,
    required this.hasMemberDiscount,
    required this.paymentRoute,
  });

  final int itemCount;
  final int total;
  final bool hasMemberDiscount;
  final PartnerPaymentRoute? paymentRoute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CoolCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF06152D), Color(0xFF0A2250), Color(0xFF13386D)],
      ),
      borderColor: RsColors.rsBlueBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Verified checkout',
            style: theme.textTheme.labelLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
              letterSpacing: 0.35,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          LayoutBuilder(
            builder: (context, constraints) {
              final useStackedHeader = constraints.maxWidth < 320;
              final statusChip = _CheckoutSignalChip(
                icon: hasMemberDiscount
                    ? Icons.workspace_premium_outlined
                    : Icons.verified_outlined,
                label: hasMemberDiscount
                    ? 'Member pricing live'
                    : 'Official store',
                highlighted: true,
              );

              if (useStackedHeader) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Official Checkout Desk',
                      style: context.coolText.rayon(
                        const TextStyle(fontSize: 28),
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Verified club fulfilment, disciplined totals, and payment confirmation before release.',
                      style: context.coolText.rayon(
                        const TextStyle(fontSize: 15),
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.8),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    statusChip,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Official Checkout Desk',
                          style: context.coolText.rayon(
                            const TextStyle(fontSize: 28),
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Verified club fulfilment, disciplined totals, and payment confirmation before release.',
                          style: context.coolText.rayon(
                            const TextStyle(fontSize: 15),
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.8),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: statusChip,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CheckoutSignalChip(
                icon: Icons.shopping_bag_outlined,
                label: '$itemCount items under review',
              ),
              _CheckoutSignalChip(
                icon: Icons.payments_outlined,
                label: _ShopCheckoutScreenState._fmtRwf(total),
              ),
              _CheckoutSignalChip(
                icon: paymentRoute == null
                    ? Icons.timelapse_rounded
                    : Icons.shield_outlined,
                label: paymentRoute == null
                    ? 'Payment route syncing'
                    : '${paymentRoute!.providerLabel} active',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CheckoutSignalChip extends StatelessWidget {
  const _CheckoutSignalChip({
    required this.icon,
    required this.label,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: highlighted
            ? RsColors.rsGold.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: highlighted
              ? RsColors.rsGold.withValues(alpha: 0.24)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: highlighted
                ? RsColors.rsGoldLight
                : Colors.white.withValues(alpha: 0.76),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.coolText.rayon(
                const TextStyle(fontSize: 16),
                fontWeight: FontWeight.w800,
                color: highlighted ? RsColors.rsGoldLight : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShopCheckoutOverviewCard extends StatelessWidget {
  const _ShopCheckoutOverviewCard({
    required this.products,
    required this.shop,
    required this.itemCount,
    required this.subtotal,
    required this.discountAmount,
    required this.deliveryFee,
    required this.total,
  });

  final List<RsProduct> products;
  final RayonShopCatalogData shop;
  final int itemCount;
  final int subtotal;
  final int discountAmount;
  final int deliveryFee;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final hasMemberDiscount = shop.hasMemberDiscount;

    return CoolCard(
      borderColor: colors.borderStrong,
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
                      'Review order',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x2),
                    Text(
                      '$itemCount item${itemCount == 1 ? '' : 's'} · ${products.length} product${products.length == 1 ? '' : 's'}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasMemberDiscount)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: RsColors.rsGold.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: RsColors.rsGold.withValues(alpha: 0.28),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    'GOLD -10%',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      fontFamily: GoogleFonts.dmMono().fontFamily,
                      color: RsColors.rsGoldLight,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: CoolSpace.x6),
          for (var index = 0; index < products.length; index++) ...[
            _CheckoutLineItemRow(
              product: products[index],
              quantity: shop.quantityFor(products[index].id),
              hasMemberDiscount: hasMemberDiscount,
            ),
            if (index < products.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Divider(height: 1, color: colors.border),
              ),
          ],
          const SizedBox(height: CoolSpace.x6),
          Divider(color: colors.border),
          const SizedBox(height: CoolSpace.x4),
          _SummaryRow(
            label: context.l10n.subtotal,
            value: _ShopCheckoutScreenState._fmtRwf(subtotal),
          ),
          if (discountAmount > 0)
            _SummaryRow(
              label: context.l10n.memberDiscount,
              value: '-${_ShopCheckoutScreenState._fmtRwf(discountAmount)}',
              valueColor: colors.accent,
            ),
          _SummaryRow(
            label: 'Pickup / delivery',
            value: deliveryFee == 0
                ? 'Free'
                : _ShopCheckoutScreenState._fmtRwf(deliveryFee),
          ),
          const SizedBox(height: CoolSpace.x2),
          Divider(color: colors.border),
          const SizedBox(height: CoolSpace.x3),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              Text(
                _ShopCheckoutScreenState._fmtRwf(total),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontFamily: GoogleFonts.dmMono().fontFamily,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CheckoutLineItemRow extends StatelessWidget {
  const _CheckoutLineItemRow({
    required this.product,
    required this.quantity,
    required this.hasMemberDiscount,
  });

  final RsProduct product;
  final int quantity;
  final bool hasMemberDiscount;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final lineTotal = product.price * quantity;
    final discountedTotal = hasMemberDiscount
        ? (lineTotal * 0.9).round()
        : lineTotal;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colors.commerceSurface,
            borderRadius: BorderRadius.circular(CoolRadii.sm),
            border: Border.all(color: colors.border),
          ),
          alignment: Alignment.center,
          child: Text(product.imageEmoji, style: const TextStyle(fontSize: 20)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.name,
                style: context.coolText.rayon(
                  const TextStyle(fontSize: 16),
                  fontWeight: FontWeight.w800,
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: CoolSpace.x1),
              Text(
                'Qty $quantity',
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.secondaryText,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          _ShopCheckoutScreenState._fmtRwf(discountedTotal),
          style: GoogleFonts.dmMono(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: colors.primaryText,
          ),
        ),
      ],
    );
  }
}

class _ShopCheckoutActionCard extends StatelessWidget {
  const _ShopCheckoutActionCard({
    required this.addressController,
    required this.total,
    this.onSubmit,
    this.paymentRoute,
  });

  final TextEditingController addressController;
  final int total;
  final VoidCallback? onSubmit;
  final PartnerPaymentRoute? paymentRoute;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final paymentLabel = paymentRoute == null
        ? 'Payment route unavailable'
        : 'Pay ${paymentRoute!.amountLabel(total)} via ${paymentRoute!.providerLabel}';
    final paymentTitle = paymentRoute == null
        ? 'Checkout unavailable'
        : paymentRoute!.providerLabel;
    final paymentBody = paymentRoute == null
        ? 'Checkout opens once partner payment routing is active.'
        : 'Pay ${paymentRoute!.amountLabel(total)} to ${paymentRoute!.payToLabel}. Order confirmation follows after ${paymentRoute!.reconciliationLabel}.';

    return CoolCard(
      borderColor: colors.borderStrong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fulfilment and payment',
            style: context.coolText.rayon(
              const TextStyle(fontSize: 22),
              fontWeight: FontWeight.w800,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Leave the address empty for club pickup. Add a destination only when delivery should be coordinated.',
            style: context.coolText.rayon(
              const TextStyle(fontSize: 15),
              fontWeight: FontWeight.w600,
              color: colors.secondaryText,
              height: 1.4,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          CoolTextField(
            controller: addressController,
            label: context.l10n.address,
            hint: 'Kigali Pele pickup',
            maxLines: 2,
          ),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CheckoutSignalChip(
                icon: Icons.verified_outlined,
                label: 'Order verified before release',
              ),
              _CheckoutSignalChip(
                icon: Icons.receipt_long_outlined,
                label: 'Receipt after reconciliation',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: RsColors.rsBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: RsColors.rsBlueBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: RsColors.rsBlueGlow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.phone_in_talk_rounded,
                    color: RsColors.rsWhite,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        paymentTitle,
                        style: context.coolText.rayon(
                          const TextStyle(fontSize: 14),
                          fontWeight: FontWeight.w800,
                          color: RsColors.rsWhite,
                        ),
                      ),
                      const SizedBox(height: CoolSpace.x1),
                      Text(
                        paymentBody,
                        style: context.coolText.rayon(
                          const TextStyle(fontSize: 16),
                          fontWeight: FontWeight.w600,
                          color: colors.secondaryText,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: CoolSpace.x4),
          CoolButton(
            label: paymentLabel,
            isDisabled: onSubmit == null,
            onTap: onSubmit,
            icon: Icons.lock_outline_rounded,
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
    required this.paymentRoute,
    required this.onRefreshStatus,
    required this.onBackToShop,
    required this.onViewOrders,
    required this.useProductionRedesign,
  });

  final String orderId;
  final int total;
  final AsyncValue<List<RsShopOrder>> orderAsync;
  final RsShopOrder? order;
  final String message;
  final PartnerPaymentRoute? paymentRoute;
  final VoidCallback onRefreshStatus;
  final VoidCallback onBackToShop;
  final VoidCallback onViewOrders;
  final bool useProductionRedesign;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final status = order?.status ?? OrderStatus.pending;
    final color = _statusColor(context, status);

    return Center(
      child: Column(
        children: [
          if (useProductionRedesign) ...[
            _CheckoutCommandCard(
              itemCount: 1,
              total: total,
              hasMemberDiscount: false,
              paymentRoute: paymentRoute,
            ),
            const SizedBox(height: 18),
          ],
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.16),
              border: Border.all(
                color: color.withValues(alpha: 0.42),
                width: 2.5,
              ),
            ),
            alignment: Alignment.center,
            child: Icon(_statusIcon(status), size: 44, color: color),
          ),
          const SizedBox(height: CoolSpace.x6),
          Text(
            _statusHeadline(status),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: RsColors.rsWhite,
              letterSpacing: -1.0,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          Text(
            _statusBody(status, total, message, paymentRoute),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.secondaryText,
              height: 1.6,
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
            label: context.l10n.refreshOrderStatus,
            variant: CoolButtonVariant.secondary,
            onTap: onRefreshStatus,
            icon: Icons.sync_rounded,
          ),
          const SizedBox(height: 10),
          CoolButton(label: context.l10n.backToShop, onTap: onBackToShop),
          const SizedBox(height: 10),
          CoolButton(
            label: context.l10n.viewProfileOrders,
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
      final colors = context.coolSemanticColors;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Order syncing',
            style: context.coolText.rayon(
              const TextStyle(fontSize: 14),
              fontWeight: FontWeight.w700,
              color: RsColors.rsWhite,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Order created',
            style: context.coolText.rayon(
              const TextStyle(fontSize: 15),
              fontWeight: FontWeight.w700,
              color: colors.secondaryText,
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
                style: context.coolText.rayon(
                  const TextStyle(fontSize: 14),
                  fontWeight: FontWeight.w700,
                  color: RsColors.rsWhite,
                ),
              ),
            ),
            _OrderStatusChip(status: orderValue.status),
          ],
        ),
        const SizedBox(height: CoolSpace.x3),
        _SummaryRow(label: context.l10n.orderId, value: orderValue.id),
        _SummaryRow(
          label: context.l10n.amount,
          value: _ShopCheckoutScreenState._fmtRwf(orderValue.total),
          valueColor: RsColors.rsWhite,
        ),
        _SummaryRow(
          label: context.l10n.momoRef,
          value: orderValue.momoReference,
        ),
        _SummaryRow(
          label: context.l10n.delivery,
          value: orderValue.deliveryAddress,
        ),
        _SummaryRow(
          label: context.l10n.created,
          value: DateFormat('dd MMM, HH:mm').format(orderValue.createdAt),
        ),
        if (orderValue.status == OrderStatus.pending) ...[
          const SizedBox(height: 6),
          Text(
            'Fulfillment starts after payment',
            style: context.coolText.rayon(
              const TextStyle(fontSize: 15),
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
    final colors = context.coolSemanticColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Checking backend order state...',
          style: context.coolText.rayon(
            const TextStyle(fontSize: 14),
            fontWeight: FontWeight.w700,
            color: RsColors.rsWhite,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Order created',
          style: context.coolText.rayon(
            const TextStyle(fontSize: 15),
            fontWeight: FontWeight.w700,
            color: colors.secondaryText,
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
    final colors = context.coolSemanticColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Order status unavailable',
          style: context.coolText.rayon(
            const TextStyle(fontSize: 14),
            fontWeight: FontWeight.w700,
            color: RsColors.rsWhite,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Order created',
          style: context.coolText.rayon(
            const TextStyle(fontSize: 15),
            fontWeight: FontWeight.w700,
            color: colors.secondaryText,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: onRefreshStatus,
          icon: const Icon(Icons.sync_rounded, size: 18),
          label: Text(context.l10n.tryAgain),
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
    final color = _statusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        status.label.toUpperCase(),
        style: context.coolText.rayon(
          const TextStyle(fontSize: 14),
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
    final colors = context.coolSemanticColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80),
      child: CoolCard(
        backgroundColor: colors.cardSurfaceStrong.withValues(alpha: 0.88),
        borderColor: colors.borderStrong,
        child: Column(
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: colors.commerceSurface,
                borderRadius: BorderRadius.circular(CoolRadii.lg),
                border: Border.all(color: colors.borderStrong),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.shopping_cart_outlined,
                size: 34,
                color: colors.primaryText,
              ),
            ),
            const SizedBox(height: CoolSpace.x5),
            Text(
              'Add products from the',
              textAlign: TextAlign.center,
              style: context.coolText.rayon(
                const TextStyle(fontSize: 15),
                fontWeight: FontWeight.w600,
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: CoolSpace.x2),
            Text(
              'Your cart is empty',
              style: context.coolText.rayonCondensed(
                const TextStyle(fontSize: 30),
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 18),
            CoolButton(label: context.l10n.backToShop, onTap: onBackToShop),
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
    OrderStatus.paid => 'Payment Received',
    OrderStatus.confirmed => 'Order Confirmed',
    OrderStatus.packed => 'Order Packed',
    OrderStatus.shipped => 'Order Shipped',
    OrderStatus.fulfilled => 'Order Fulfilled',
    OrderStatus.delivered => 'Order Delivered',
    OrderStatus.cancelled => 'Order Cancelled',
  };
}

Color _statusColor(BuildContext context, OrderStatus status) {
  final colors = context.coolSemanticColors;
  return switch (status) {
    OrderStatus.pending => RsColors.rsGoldLight,
    OrderStatus.paid => colors.accent,
    OrderStatus.confirmed => colors.accent,
    OrderStatus.packed => RsColors.rsBluePale,
    OrderStatus.shipped => RsColors.rsBluePale,
    OrderStatus.fulfilled || OrderStatus.delivered => RsColors.rsWhite,
    OrderStatus.cancelled => colors.tertiaryText,
  };
}

IconData _statusIcon(OrderStatus status) {
  return switch (status) {
    OrderStatus.pending => Icons.schedule_rounded,
    OrderStatus.paid ||
    OrderStatus.confirmed => Icons.check_circle_outline_rounded,
    OrderStatus.packed => Icons.inventory_2_outlined,
    OrderStatus.shipped => Icons.local_shipping_outlined,
    OrderStatus.fulfilled || OrderStatus.delivered => Icons.done_all_rounded,
    OrderStatus.cancelled => Icons.block_outlined,
  };
}

String _statusHeadline(OrderStatus status) {
  return switch (status) {
    OrderStatus.pending => 'Waiting for Payment Confirmation',
    OrderStatus.paid => 'Payment Received',
    OrderStatus.confirmed => 'Order Confirmed',
    OrderStatus.packed => 'Order Packed',
    OrderStatus.shipped => 'Order on the Way',
    OrderStatus.fulfilled || OrderStatus.delivered => 'Order Delivered',
    OrderStatus.cancelled => 'Order Cancelled',
  };
}

String _statusBody(
  OrderStatus status,
  int total,
  String openedMessage,
  PartnerPaymentRoute? paymentRoute,
) {
  final paymentDetails = paymentRoute == null
      ? 'backend payment routing'
      : paymentRoute.payToLabel;
  final amountLabel =
      paymentRoute?.amountLabel(total) ??
      _ShopCheckoutScreenState._fmtRwf(total);
  final receiptLogic = paymentRoute == null
      ? 'SMS reconciliation'
      : 'SMS reconciliation for ${paymentRoute.reconciliationLabel}';

  return switch (status) {
    OrderStatus.pending =>
      '$openedMessage Approve payment to $paymentDetails for $amountLabel. Fees ${paymentRoute?.feesLabel() ?? '0 RWF'}. We issue the receipt after $receiptLogic.',
    OrderStatus.paid => 'Payment received. Your order is being processed.',
    OrderStatus.confirmed =>
      'Payment confirmed. Order is in the fulfillment queue.',
    OrderStatus.packed =>
      'Your order has been packed and is ready for pickup or handover.',
    OrderStatus.shipped =>
      'This order has been confirmed and handed over for delivery.',
    OrderStatus.fulfilled || OrderStatus.delivered =>
      'This Rayon Sports order has been marked as delivered.',
    OrderStatus.cancelled =>
      'Order cancelled. Refresh or contact support if you paid.',
  };
}
