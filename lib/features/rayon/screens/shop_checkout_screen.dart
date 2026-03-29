import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/app_routes.dart';

import '../../../../core/providers/referral_providers.dart';
import '../../../../core/status/cool_status_awarder.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/cool_toast.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_text_field.dart';
import '../models/rs_models.dart';

import '../rayon_payment.dart';
import '../providers/rayon_sports_provider.dart';
import '../../../../shared/widgets/core_app_scaffold.dart';
import '../widgets/rayon_state_views.dart';
import '../../../../core/l10n/l10n.dart';

part '../widgets/shop_checkout_parts.dart';

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
    final paymentRoute = ref.watch(rayonPaymentRouteProvider).valueOrNull;
    final ordersAsync = _openedOrderId == null
        ? const AsyncData<List<RsShopOrder>>(<RsShopOrder>[])
        : ref.watch(rayonShopOrdersProvider);
    final openedOrder = _findOrderById(ordersAsync.valueOrNull, _openedOrderId);

    return CoreAppScaffold(
      title: _openedOrderId == null
          ? 'Checkout'
          : _checkoutTitle(openedOrder?.status ?? OrderStatus.pending),
      fallbackLocation: AppRoutes.rayonShop,
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
                      paymentRoute: paymentRoute,
                      onRefreshStatus: () =>
                          ref.invalidate(rayonShopOrdersProvider),
                      onBackToShop: () => context.go(AppRoutes.rayonShop),
                      onViewOrders: () => context.go(AppRoutes.rayonProfile),

                    ),
                  ),
                ),
              ],
            );
          }

          final products = shop.selectedProducts();

          if (products.isEmpty) {
            return _EmptyCheckout(
              onBackToShop: () => context.go(AppRoutes.rayonShop),
            );
          }

          final subtotal = shop.subtotalFor(products);
          final discountAmount = shop.discountFor(subtotal);
          final itemCount = products.fold<int>(
            0,
            (sum, product) => sum + shop.quantityFor(product.id),
          );
          const delivery = 0;
          final total = subtotal - discountAmount + delivery;

          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 96),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    children: [
                      _CheckoutCommandCard(
                        itemCount: itemCount,
                        total: total,
                        hasMemberDiscount: shop.hasMemberDiscount,
                        paymentRoute: paymentRoute,
                      ),
                      const SizedBox(height: CoolSpace.x4),
                      _ShopCheckoutOverviewCard(
                        products: products,
                        shop: shop,
                        itemCount: itemCount,
                        subtotal: subtotal,
                        discountAmount: discountAmount,
                        deliveryFee: delivery,
                        total: total,
                      ),
                      const SizedBox(height: CoolSpace.x4),
                      _ShopCheckoutActionCard(
                        addressController: _addressController,
                        total: total,
                        paymentRoute: paymentRoute,
                        onSubmit: paymentRoute == null
                            ? null
                            : () async {
                                final notifier = ref.read(
                                  rayonSportsProvider.notifier,
                                );
                                try {
                                  final referralInviteId = _referralInviteId;
                                  final result = await notifier.checkoutShop(
                                    products: products,
                                    membership: shop.membership,
                                    quantities: shop.cart,
                                    deliveryAddress:
                                        _addressController.text.trim().isEmpty
                                        ? 'Kigali Pele pickup'
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
                                  ref
                                      .read(
                                        rayonCartControllerProvider.notifier,
                                      )
                                      .clearCart();
                                  if (referralInviteId != null &&
                                      referralInviteId.isNotEmpty) {
                                    ref
                                        .read(
                                          activeReferralAttributionProvider
                                              .notifier,
                                        )
                                        .clearIfMatches(referralInviteId);
                                  }
                                  CoolToast.info(context, result.message);
                                } catch (error) {
                                  if (!context.mounted) {
                                    return;
                                  }
                                  CoolToast.error(context, error.toString());
                                }
                              },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        loading: RayonLoadingView.new,
        error: (error, _) => RayonErrorView(
          message: error.toString(),
          onRetry: () {
            ref.invalidate(rayonShopProductsProvider);
            ref.invalidate(rayonUserMembershipProvider);
          },
        ),
      ),
    );
  }

  static String _fmtRwf(int amount) {
    return '${NumberFormat.decimalPattern('en').format(amount)} RWF';
  }
}
