import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../auth/providers/auth_provider.dart';
import '../rayon/models/rs_models.dart';
import '../rayon/rayon_payment.dart';
import '../repositories/rayon_sports_repository.dart';

final rayonSportsRepositoryProvider = Provider<RayonSportsRepository>((ref) {
  return RayonSportsRepository();
});

final rayonCurrentUserIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authProvider);
  return authState.user?.id ?? authState.session?.user.id;
});

final rayonPartnerIdProvider = FutureProvider.autoDispose<String>((ref) async {
  final repository = ref.watch(rayonSportsRepositoryProvider);
  return await repository.getRayonPartnerId() ?? '';
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

final rayonCartProvider = Provider<Map<String, int>>((ref) {
  return ref.watch(rayonSportsProvider.select((state) => state.cart));
});

final rayonCartCountProvider = Provider<int>((ref) {
  final cart = ref.watch(rayonCartProvider);
  return cart.values.fold<int>(0, (sum, quantity) => sum + quantity);
});

final rayonMembershipProvider = Provider<AsyncValue<RsFanMembership?>>((ref) {
  final data = ref.watch(rayonSportsDataProvider);
  return data.whenData((value) => value.membership);
});

final rayonAchievementsProvider = Provider<AsyncValue<List<RsAchievement>>>((
  ref,
) {
  final data = ref.watch(rayonSportsDataProvider);
  return data.whenData((value) => value.achievements);
});

final rayonMatchesProvider = Provider<AsyncValue<List<RsMatch>>>((ref) {
  final data = ref.watch(rayonSportsDataProvider);
  return data.whenData((value) => value.matches);
});

final rayonNextMatchProvider = Provider<AsyncValue<RsMatch?>>((ref) {
  final matches = ref.watch(rayonMatchesProvider);
  return matches.whenData((items) => items.isEmpty ? null : items.first);
});

final rayonInitiativesProvider = Provider<AsyncValue<List<RsInitiative>>>((
  ref,
) {
  final data = ref.watch(rayonSportsDataProvider);
  return data.whenData(
    (value) => value.initiatives
        .where((initiative) => initiative.isActive)
        .toList(growable: false),
  );
});

final rayonTicketsProvider = Provider<AsyncValue<List<RsTicket>>>((ref) {
  final data = ref.watch(rayonSportsDataProvider);
  return data.whenData((value) => value.tickets);
});

final rayonLoadedPartnerIdProvider = Provider<AsyncValue<String>>((ref) {
  final data = ref.watch(rayonSportsDataProvider);
  return data.whenData((value) => value.partnerId);
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

final rayonClubDirectoryProvider = Provider<AsyncValue<RayonClubDirectoryData>>(
  (ref) {
    final data = ref.watch(rayonSportsDataProvider);
    return data.whenData(
      (value) => RayonClubDirectoryData(
        clubs: value.clubs,
        joinedClubIds: value.joinedClubIds,
      ),
    );
  },
);

final rayonClubDetailProvider =
    Provider.family<AsyncValue<RayonClubDetailData>, String>((ref, clubId) {
      final data = ref.watch(rayonSportsDataProvider);
      return data.whenData(
        (value) => RayonClubDetailData(
          club: value.clubById(clubId),
          joined: value.joinedClubIds.contains(clubId),
          achievements: value.achievements,
        ),
      );
    });

final rayonShopCatalogProvider = Provider<AsyncValue<RayonShopCatalogData>>((
  ref,
) {
  final data = ref.watch(rayonSportsDataProvider);
  final cart = ref.watch(rayonCartProvider);
  return data.whenData(
    (value) => RayonShopCatalogData(
      products: value.products,
      membership: value.membership,
      cart: cart,
    ),
  );
});

final rayonTicketHubProvider = Provider<AsyncValue<RayonTicketHubData>>((ref) {
  final data = ref.watch(rayonSportsDataProvider);
  return data.whenData(
    (value) => RayonTicketHubData(
      membership: value.membership,
      matches: value.matches,
      tickets: value.tickets,
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
    final normalizedSeat = seatType.toLowerCase() == 'vip' ? 'VIP' : 'General';
    final unitPrice = normalizedSeat == 'VIP'
        ? match.ticketVipPrice
        : match.ticketGeneralPrice;
    final totalAmount = unitPrice * quantity;

    return _runAction(
      () async {
        await _repository.purchaseTickets(
          matchId: match.id,
          userId: userId,
          seatType: seatType,
          quantity: quantity,
          referralInviteId: referralInviteId,
        );
        await _softReload();
      },
      successMessage:
          'Ticket checkout opened in MTN MoMo code $rayonSportsMomoCode for ${_fmtRwf(totalAmount)}. Your tickets stay pending until payment confirmation arrives.',
    );
  }

  Future<RayonSupportCheckoutResult> supportInitiative({
    required String initiativeId,
    required int amount,
    String? referralInviteId,
  }) async {
    final userId = _requireUser();
    state = state.copyWith(action: const AsyncLoading<String?>());

    try {
      final contributionId = await _repository.supportInitiative(
        userId: userId,
        initiativeId: initiativeId,
        amount: amount,
        referralInviteId: referralInviteId,
      );
      await _softReload();
      final message =
          'Support checkout opened in MTN MoMo code $rayonSportsMomoCode for ${_fmtRwf(amount)}.';
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
      final message =
          'Shop checkout opened in MTN MoMo code $rayonSportsMomoCode for ${_fmtRwf(total)}.';
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

  static String _fmtRwf(int amount) {
    return '${NumberFormat.decimalPattern('en').format(amount)} RWF';
  }
}
