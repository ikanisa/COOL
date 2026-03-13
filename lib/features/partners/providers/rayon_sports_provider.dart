import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/hive_providers.dart';

import '../../auth/providers/auth_provider.dart';
import '../../../core/providers/supabase_client_provider.dart';
import '../rayon/models/rs_models.dart';

import '../rayon/rayon_payment.dart';
import '../repositories/rayon_sports_repository.dart';

final rayonSportsRepositoryProvider = Provider<RayonSportsRepository>((ref) {
  return RayonSportsRepository(
    client: ref.read(supabaseClientProvider),
    openBox: ref.read(hiveOpenBoxProvider),
  );
});

final rayonCurrentUserIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authProvider);
  return authState.user?.id ?? authState.session?.user.id;
});

final rayonPartnerIdProvider = FutureProvider.autoDispose<String>((ref) async {
  final repository = ref.watch(rayonSportsRepositoryProvider);
  return await repository.getRayonPartnerId() ?? '';
});

final rayonPaymentRouteProvider =
    FutureProvider.autoDispose<PartnerPaymentRoute?>((ref) async {
      final repository = ref.watch(rayonSportsRepositoryProvider);
      try {
        return await repository.getActivePaymentRoute();
      } catch (_) {
        return null;
      }
    });

final rayonWalletAvailabilityProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  final repository = ref.watch(rayonSportsRepositoryProvider);
  return repository.isGoogleWalletOperationallyReady();
});

final rayonSportsProvider =
    StateNotifierProvider<RayonSportsNotifier, RayonSportsState>((ref) {
      final repository = ref.watch(rayonSportsRepositoryProvider);
      final authState = ref.watch(authProvider);
      return RayonSportsNotifier(
        repository: repository,
        userId: authState.user?.id ?? authState.session?.user.id,
      );
    });

final rayonSportsDataProvider = Provider<AsyncValue<RayonSportsData>>((ref) {
  return ref.watch(rayonSportsProvider.select((state) => state.data));
});

final rayonActionLoadingProvider = Provider<bool>((ref) {
  return ref.watch(
    rayonSportsProvider.select((state) => state.action.isLoading),
  );
});

final rayonCartControllerProvider =
    StateNotifierProvider<RayonCartController, Map<String, int>>((ref) {
      return RayonCartController();
    });

final rayonCartProvider = Provider<Map<String, int>>((ref) {
  return ref.watch(rayonCartControllerProvider);
});

final rayonCartCountProvider = Provider<int>((ref) {
  final cart = ref.watch(rayonCartProvider);
  return cart.values.fold<int>(0, (sum, quantity) => sum + quantity);
});

final rayonUserMembershipProvider =
    FutureProvider.autoDispose<RsFanMembership?>((ref) async {
      final userId = ref.watch(rayonCurrentUserIdProvider);
      if (userId == null || userId.isEmpty) {
        return null;
      }

      final partnerId = await ref.watch(rayonPartnerIdProvider.future);
      if (partnerId.isEmpty) {
        return null;
      }

      final repository = ref.watch(rayonSportsRepositoryProvider);
      return repository.getFanMembership(userId, partnerId);
    });

final rayonUserAchievementsProvider =
    FutureProvider.autoDispose<List<RsAchievement>>((ref) async {
      final userId = ref.watch(rayonCurrentUserIdProvider);
      if (userId == null || userId.isEmpty) {
        return const <RsAchievement>[];
      }

      final partnerId = await ref.watch(rayonPartnerIdProvider.future);
      if (partnerId.isEmpty) {
        return const <RsAchievement>[];
      }

      final repository = ref.watch(rayonSportsRepositoryProvider);
      return repository.getAchievements(userId: userId, partnerId: partnerId);
    });

final rayonUserTicketsProvider = FutureProvider.autoDispose<List<RsTicket>>((
  ref,
) async {
  final userId = ref.watch(rayonCurrentUserIdProvider);
  if (userId == null || userId.isEmpty) {
    return const <RsTicket>[];
  }

  final repository = ref.watch(rayonSportsRepositoryProvider);
  return repository.getMyTickets(userId);
});

final rayonUserTicketByIdProvider =
    Provider.family<AsyncValue<RsTicket?>, String>((ref, ticketId) {
      final tickets = ref.watch(rayonUserTicketsProvider);
      return tickets.whenData((items) {
        for (final ticket in items) {
          if (ticket.id == ticketId) {
            return ticket;
          }
        }
        return null;
      });
    });

final rayonMembershipProvider = Provider<AsyncValue<RsFanMembership?>>((ref) {
  return ref.watch(rayonUserMembershipProvider);
});

final rayonAchievementsProvider = Provider<AsyncValue<List<RsAchievement>>>((
  ref,
) {
  return ref.watch(rayonUserAchievementsProvider);
});

final rayonMatchesProvider = FutureProvider.autoDispose<List<RsMatch>>((
  ref,
) async {
  final partnerId = await ref.watch(rayonPartnerIdProvider.future);
  if (partnerId.isEmpty) {
    return const <RsMatch>[];
  }

  final repository = ref.watch(rayonSportsRepositoryProvider);
  return repository.getMatches(partnerId, false);
});

final rayonNextMatchProvider = Provider<AsyncValue<RsMatch?>>((ref) {
  final matches = ref.watch(rayonMatchesProvider);
  return matches.whenData((items) => items.isEmpty ? null : items.first);
});

final rayonInitiativesProvider = FutureProvider.autoDispose<List<RsInitiative>>(
  (ref) async {
    final partnerId = await ref.watch(rayonPartnerIdProvider.future);
    if (partnerId.isEmpty) {
      return const <RsInitiative>[];
    }

    final repository = ref.watch(rayonSportsRepositoryProvider);
    return repository.getInitiatives(partnerId);
  },
);

final rayonTicketsProvider = Provider<AsyncValue<List<RsTicket>>>((ref) {
  return ref.watch(rayonUserTicketsProvider);
});

final rayonLoadedPartnerIdProvider = Provider<AsyncValue<String>>((ref) {
  return ref.watch(rayonPartnerIdProvider);
});

final rayonTicketByIdProvider = Provider.family<AsyncValue<RsTicket?>, String>((
  ref,
  ticketId,
) {
  final tickets = ref.watch(rayonTicketsProvider);
  return tickets.whenData((items) {
    for (final ticket in items) {
      if (ticket.id == ticketId) {
        return ticket;
      }
    }
    return null;
  });
});

class RayonClubDirectoryData {
  const RayonClubDirectoryData({
    required this.clubs,
    required this.joinedClubIds,
  });

  final List<RsFanClub> clubs;
  final Set<String> joinedClubIds;

  RsFanClub? clubById(String clubId) {
    for (final club in clubs) {
      if (club.id == clubId) {
        return club;
      }
    }
    return null;
  }
}

class RayonClubDetailData {
  const RayonClubDetailData({
    required this.club,
    required this.joined,
    required this.achievements,
  });

  final RsFanClub? club;
  final bool joined;
  final List<RsAchievement> achievements;
}

class RayonShopCatalogData {
  const RayonShopCatalogData({
    required this.products,
    required this.membership,
    required this.cart,
  });

  final List<RsProduct> products;
  final RsFanMembership? membership;
  final Map<String, int> cart;

  bool get hasMemberDiscount =>
      membership?.tier == FanTier.gold || membership?.tier == FanTier.platinum;

  bool get hasItems => cart.values.any((quantity) => quantity > 0);

  int get cartItemCount =>
      cart.values.fold<int>(0, (sum, quantity) => sum + quantity);

  int quantityFor(String productId) => cart[productId] ?? 0;

  List<RsProduct> selectedProducts() {
    return products
        .where((product) => quantityFor(product.id) > 0)
        .toList(growable: false);
  }

  int subtotalFor(Iterable<RsProduct> selectedProducts) {
    return selectedProducts.fold<int>(
      0,
      (sum, product) => sum + product.price * quantityFor(product.id),
    );
  }

  int discountFor(int subtotal) {
    return hasMemberDiscount ? (subtotal * 0.10).round() : 0;
  }

  int get cartTotal => subtotalFor(products);
}

class RayonTicketHubData {
  const RayonTicketHubData({
    required this.membership,
    required this.matches,
    required this.tickets,
  });

  final RsFanMembership? membership;
  final List<RsMatch> matches;
  final List<RsTicket> tickets;

  FanTier get currentTier => membership?.tier ?? FanTier.blue;

  List<RsMatch> get onSaleMatches =>
      matches.where((match) => match.isOnSale).toList(growable: false);

  List<RsMatch> get upcomingMatches =>
      matches.where((match) => !match.isOnSale).toList(growable: false);
}

class RayonCartController extends StateNotifier<Map<String, int>> {
  RayonCartController() : super(const <String, int>{});

  void addToCart(String productId) {
    final cart = Map<String, int>.from(state);
    cart[productId] = (cart[productId] ?? 0) + 1;
    state = cart;
  }

  void removeFromCart(String productId) {
    final cart = Map<String, int>.from(state);
    final current = cart[productId] ?? 0;
    if (current <= 1) {
      cart.remove(productId);
    } else {
      cart[productId] = current - 1;
    }
    state = cart;
  }

  void clearCart() {
    state = const <String, int>{};
  }
}

AsyncValue<T> _combineAsync2<A, B, T>(
  AsyncValue<A> first,
  AsyncValue<B> second,
  T Function(A firstValue, B secondValue) builder,
) {
  if (first.hasError) {
    return AsyncError<T>(first.error!, first.stackTrace ?? StackTrace.current);
  }
  if (second.hasError) {
    return AsyncError<T>(
      second.error!,
      second.stackTrace ?? StackTrace.current,
    );
  }
  if (first.isLoading || second.isLoading) {
    return AsyncLoading<T>();
  }

  return AsyncData<T>(builder(first.requireValue, second.requireValue));
}

AsyncValue<T> _combineAsync3<A, B, C, T>(
  AsyncValue<A> first,
  AsyncValue<B> second,
  AsyncValue<C> third,
  T Function(A firstValue, B secondValue, C thirdValue) builder,
) {
  if (first.hasError) {
    return AsyncError<T>(first.error!, first.stackTrace ?? StackTrace.current);
  }
  if (second.hasError) {
    return AsyncError<T>(
      second.error!,
      second.stackTrace ?? StackTrace.current,
    );
  }
  if (third.hasError) {
    return AsyncError<T>(third.error!, third.stackTrace ?? StackTrace.current);
  }
  if (first.isLoading || second.isLoading || third.isLoading) {
    return AsyncLoading<T>();
  }

  return AsyncData<T>(
    builder(first.requireValue, second.requireValue, third.requireValue),
  );
}

final rayonFanClubsProvider = FutureProvider.autoDispose<List<RsFanClub>>((
  ref,
) async {
  final partnerId = await ref.watch(rayonPartnerIdProvider.future);
  if (partnerId.isEmpty) {
    return const <RsFanClub>[];
  }

  final repository = ref.watch(rayonSportsRepositoryProvider);
  return repository.getFanClubs(partnerId, null);
});

final rayonJoinedClubIdsProvider = FutureProvider.autoDispose<Set<String>>((
  ref,
) async {
  final userId = ref.watch(rayonCurrentUserIdProvider);
  if (userId == null || userId.isEmpty) {
    return const <String>{};
  }

  final repository = ref.watch(rayonSportsRepositoryProvider);
  final clubs = await repository.getUserClubs(userId);
  return clubs.map((club) => club.id).toSet();
});

final rayonShopProductsProvider = FutureProvider.autoDispose<List<RsProduct>>((
  ref,
) async {
  final partnerId = await ref.watch(rayonPartnerIdProvider.future);
  if (partnerId.isEmpty) {
    return const <RsProduct>[];
  }

  final repository = ref.watch(rayonSportsRepositoryProvider);
  return repository.getProducts(partnerId, null);
});

final rayonClubDirectoryProvider = Provider<AsyncValue<RayonClubDirectoryData>>(
  (ref) {
    final clubs = ref.watch(rayonFanClubsProvider);
    final joinedClubIds = ref.watch(rayonJoinedClubIdsProvider);
    return _combineAsync2(
      clubs,
      joinedClubIds,
      (clubsValue, joinedClubIdsValue) => RayonClubDirectoryData(
        clubs: clubsValue,
        joinedClubIds: joinedClubIdsValue,
      ),
    );
  },
);

final rayonClubDetailProvider =
    Provider.family<AsyncValue<RayonClubDetailData>, String>((ref, clubId) {
      final directory = ref.watch(rayonClubDirectoryProvider);
      final achievements = ref.watch(rayonUserAchievementsProvider);
      return _combineAsync2(
        directory,
        achievements,
        (directoryValue, achievementsValue) => RayonClubDetailData(
          club: directoryValue.clubById(clubId),
          joined: directoryValue.joinedClubIds.contains(clubId),
          achievements: achievementsValue,
        ),
      );
    });

final rayonShopCatalogProvider = Provider<AsyncValue<RayonShopCatalogData>>((
  ref,
) {
  final products = ref.watch(rayonShopProductsProvider);
  final membership = ref.watch(rayonUserMembershipProvider);
  final cart = ref.watch(rayonCartProvider);
  return _combineAsync2(
    products,
    membership,
    (productsValue, membershipValue) => RayonShopCatalogData(
      products: productsValue,
      membership: membershipValue,
      cart: cart,
    ),
  );
});

final rayonTicketHubProvider = Provider<AsyncValue<RayonTicketHubData>>((ref) {
  final membership = ref.watch(rayonUserMembershipProvider);
  final matches = ref.watch(rayonMatchesProvider);
  final tickets = ref.watch(rayonUserTicketsProvider);
  return _combineAsync3(
    membership,
    matches,
    tickets,
    (membershipValue, matchesValue, ticketsValue) => RayonTicketHubData(
      membership: membershipValue,
      matches: matchesValue,
      tickets: ticketsValue,
    ),
  );
});

final rayonShopOrdersProvider = FutureProvider.autoDispose<List<RsShopOrder>>((
  ref,
) async {
  final userId = ref.watch(rayonCurrentUserIdProvider);
  if (userId == null || userId.isEmpty) {
    return const <RsShopOrder>[];
  }

  final repository = ref.watch(rayonSportsRepositoryProvider);
  return repository.getMyShopOrders(userId);
});

final rayonRecentContributorsProvider = FutureProvider.autoDispose
    .family<List<RsInitiativeContribution>, String>((ref, initiativeId) async {
      final repository = ref.watch(rayonSportsRepositoryProvider);
      return repository.getRecentContributionActivity(initiativeId, 10);
    });

class RayonInitiativesSummary {
  const RayonInitiativesSummary({
    required this.totalRaised,
    required this.totalSupporters,
    required this.activeCauses,
  });

  final int totalRaised;
  final int totalSupporters;
  final int activeCauses;
}

class RayonShopCheckoutResult {
  const RayonShopCheckoutResult({
    required this.orderId,
    required this.total,
    required this.message,
  });

  final String orderId;
  final int total;
  final String message;
}

class RayonMembershipResolution {
  const RayonMembershipResolution({
    required this.membership,
    required this.created,
  });

  final RsFanMembership membership;
  final bool created;

  String get message => created
      ? 'Official Rayon membership created.'
      : 'Official Rayon membership restored.';
}

class RayonSupportCheckoutResult {
  const RayonSupportCheckoutResult({
    required this.contributionId,
    required this.amount,
    required this.message,
  });

  final String contributionId;
  final int amount;
  final String message;
}

final rayonInitiativesSummaryProvider =
    Provider<AsyncValue<RayonInitiativesSummary>>((ref) {
      final initiatives = ref.watch(rayonInitiativesProvider);
      return initiatives.whenData((items) {
        var totalRaised = 0;
        var totalSupporters = 0;

        for (final initiative in items) {
          totalRaised += initiative.raisedAmount;
          totalSupporters += initiative.supporterCount;
        }

        return RayonInitiativesSummary(
          totalRaised: totalRaised,
          totalSupporters: totalSupporters,
          activeCauses: items.length,
        );
      });
    });

class RayonSportsState {
  const RayonSportsState({
    this.data = const AsyncLoading<RayonSportsData>(),
    this.action = const AsyncData<String?>(null),
    this.cart = const <String, int>{},
  });

  final AsyncValue<RayonSportsData> data;
  final AsyncValue<String?> action;
  final Map<String, int> cart;

  RayonSportsState copyWith({
    AsyncValue<RayonSportsData>? data,
    AsyncValue<String?>? action,
    Map<String, int>? cart,
  }) {
    return RayonSportsState(
      data: data ?? this.data,
      action: action ?? this.action,
      cart: cart ?? this.cart,
    );
  }
}

class RayonSportsNotifier extends StateNotifier<RayonSportsState> {
  RayonSportsNotifier({
    required RayonSportsRepository repository,
    required String? userId,
    bool autoLoad = true,
  }) : _repository = repository,
       _userId = userId,
       super(const RayonSportsState()) {
    if (autoLoad) {
      unawaited(load());
    }
  }

  final RayonSportsRepository _repository;
  final String? _userId;

  Future<void> load() async {
    state = state.copyWith(
      data: const AsyncLoading<RayonSportsData>(),
      action: const AsyncData<String?>(null),
    );

    final result = await AsyncValue.guard(
      () => _repository.loadData(userId: _userId),
    );
    state = state.copyWith(data: result);
  }

  void addToCart(String productId) {
    final cart = Map<String, int>.from(state.cart);
    cart[productId] = (cart[productId] ?? 0) + 1;
    state = state.copyWith(cart: cart);
  }

  void removeFromCart(String productId) {
    final cart = Map<String, int>.from(state.cart);
    final current = cart[productId] ?? 0;
    if (current <= 1) {
      cart.remove(productId);
    } else {
      cart[productId] = current - 1;
    }
    state = state.copyWith(cart: cart);
  }

  void clearCart() {
    state = state.copyWith(cart: const <String, int>{});
  }

  int cartItemCount() {
    return state.cart.values.fold<int>(0, (sum, qty) => sum + qty);
  }

  int cartTotal(RayonSportsData data) {
    var total = 0;
    for (final product in data.products) {
      total += product.price * (state.cart[product.id] ?? 0);
    }
    return total;
  }

  Future<RayonMembershipResolution> ensureMembership() async {
    final userId = _requireUser();
    state = state.copyWith(action: const AsyncLoading<String?>());

    try {
      final existingMembership = await _repository.getRayonFanMembership(
        userId,
      );
      if (existingMembership != null) {
        await _softReload();
        final result = RayonMembershipResolution(
          membership: existingMembership,
          created: false,
        );
        state = state.copyWith(action: AsyncData<String?>(result.message));
        return result;
      }

      RsFanMembership membership;
      var created = true;
      try {
        membership = await _repository.createFanMembership(userId);
      } catch (_) {
        final recoveredMembership = await _repository.getRayonFanMembership(
          userId,
        );
        if (recoveredMembership == null) {
          rethrow;
        }
        membership = recoveredMembership;
        created = false;
      }

      await _softReload();
      final result = RayonMembershipResolution(
        membership: membership,
        created: created,
      );
      state = state.copyWith(action: AsyncData<String?>(result.message));
      return result;
    } catch (error, stackTrace) {
      state = state.copyWith(action: AsyncError<String?>(error, stackTrace));
      rethrow;
    }
  }

  Future<String> joinClub(String clubId) async {
    final userId = _requireUser();
    return _runAction(() async {
      await _repository.joinClub(clubId: clubId, userId: userId);
      await _softReload();
    }, successMessage: 'Fan club joined.');
  }

  Future<String> buyTicket({
    required RsMatch match,
    required String seatType,
    required int quantity,
    String? referralInviteId,
  }) async {
    final userId = _requireUser();
    final paymentRoute = await _repository.getActivePaymentRoute();
    final normalizedSeat = seatType.toLowerCase() == 'vip' ? 'VIP' : 'General';
    final unitPrice = normalizedSeat == 'VIP'
        ? match.ticketVipPrice
        : match.ticketGeneralPrice;
    final totalAmount = unitPrice * quantity;

    return _runAction(() async {
      await _repository.purchaseTickets(
        matchId: match.id,
        userId: userId,
        seatType: seatType,
        quantity: quantity,
        referralInviteId: referralInviteId,
      );
      await _softReload();
    }, successMessage: _ticketCheckoutMessage(paymentRoute, totalAmount));
  }

  Future<RayonSupportCheckoutResult> supportInitiative({
    required String initiativeId,
    required int amount,
    String? referralInviteId,
  }) async {
    final userId = _requireUser();
    final paymentRoute = await _repository.getActivePaymentRoute();
    state = state.copyWith(action: const AsyncLoading<String?>());

    try {
      final contributionId = await _repository.supportInitiative(
        userId: userId,
        initiativeId: initiativeId,
        amount: amount,
        referralInviteId: referralInviteId,
      );
      await _softReload();
      final message = _supportCheckoutMessage(paymentRoute, amount);
      state = state.copyWith(action: AsyncData<String?>(message));
      return RayonSupportCheckoutResult(
        contributionId: contributionId,
        amount: amount,
        message: message,
      );
    } catch (error, stackTrace) {
      state = state.copyWith(action: AsyncError<String?>(error, stackTrace));
      rethrow;
    }
  }

  Future<RayonShopCheckoutResult> checkoutShop({
    required List<RsProduct> products,
    required RsFanMembership? membership,
    required Map<String, int> quantities,
    required String deliveryAddress,
    String? referralInviteId,
  }) async {
    final userId = _requireUser();
    final paymentRoute = await _repository.getActivePaymentRoute();
    final subtotal = products.fold<int>(
      0,
      (sum, product) => sum + product.price * (quantities[product.id] ?? 0),
    );
    final hasMemberDiscount =
        membership?.tier == FanTier.gold ||
        membership?.tier == FanTier.platinum;
    final discountAmount = hasMemberDiscount ? (subtotal * 0.10).round() : 0;
    final total = subtotal - discountAmount;

    state = state.copyWith(action: const AsyncLoading<String?>());

    try {
      final orderId = await _repository.placeOrder(
        userId: userId,
        products: products,
        quantities: quantities,
        deliveryAddress: deliveryAddress,
        discountAmount: discountAmount,
        referralInviteId: referralInviteId,
      );
      clearCart();
      await _softReload();
      final message = _shopCheckoutMessage(paymentRoute, total);
      state = state.copyWith(action: AsyncData<String?>(message));
      return RayonShopCheckoutResult(
        orderId: orderId,
        total: total,
        message: message,
      );
    } catch (error, stackTrace) {
      state = state.copyWith(action: AsyncError<String?>(error, stackTrace));
      rethrow;
    }
  }

  String _requireUser() {
    final userId = _userId;
    if (userId == null || userId.isEmpty) {
      throw StateError('You must be signed in to use Rayon Sports services.');
    }
    return userId;
  }

  Future<void> _softReload() async {
    final result = await AsyncValue.guard(
      () => _repository.loadData(userId: _userId),
    );
    state = state.copyWith(data: result);
  }

  Future<String> _runAction(
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    state = state.copyWith(action: const AsyncLoading<String?>());

    final result = await AsyncValue.guard(() async {
      await action();
      return successMessage;
    });

    state = state.copyWith(action: result);

    if (result.hasError) {
      throw result.error!;
    }

    return result.value ?? successMessage;
  }

  static String _ticketCheckoutMessage(
    PartnerPaymentRoute route,
    int totalAmount,
  ) {
    return 'Ticket checkout opened to ${route.payToLabel} for ${route.amountLabel(totalAmount)}. Fees ${route.feesLabel()}. Your tickets stay pending until SMS confirmation matches ${route.reconciliationLabel}.';
  }

  static String _supportCheckoutMessage(PartnerPaymentRoute route, int amount) {
    return 'Support checkout opened to ${route.payToLabel} for ${route.amountLabel(amount)}. Fees ${route.feesLabel()}. We confirm your receipt after SMS reconciliation for ${route.reconciliationLabel}.';
  }

  static String _shopCheckoutMessage(
    PartnerPaymentRoute route,
    int totalAmount,
  ) {
    return 'Shop checkout opened to ${route.payToLabel} for ${route.amountLabel(totalAmount)}. Fees ${route.feesLabel()}. Your order receipt appears after SMS reconciliation for ${route.reconciliationLabel}.';
  }
}
