import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../rayon/models/rs_models.dart';
import '../repositories/rayon_sports_repository.dart';
import 'rayon_sports_provider.dart';

// ─────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────

/// Resolves the Rayon Sports partner UUID from the database.
/// Falls back to empty string (which will cause graceful no-ops).
final rsPartnerIdProvider = FutureProvider.autoDispose<String>((ref) async {
  return ref.watch(rayonPartnerIdProvider.future);
});

// ─────────────────────────────────────────────────────────────────────
// Fan Membership
// ─────────────────────────────────────────────────────────────────────

final fanMembershipProvider = FutureProvider.autoDispose
    .family<RsFanMembership?, String>((ref, userId) async {
      final repo = ref.watch(rayonSportsRepositoryProvider);
      final partnerId = await ref.watch(rsPartnerIdProvider.future);
      if (partnerId.isEmpty) return null;
      return repo.getFanMembership(userId, partnerId);
    });

// ─────────────────────────────────────────────────────────────────────
// Member Registry
// ─────────────────────────────────────────────────────────────────────

@immutable
class MemberRegistryState {
  const MemberRegistryState({
    this.members = const [],
    this.searchQuery = '',
    this.filterTier,
    this.isLoading = false,
    this.hasMore = true,
    this.currentPage = 0,
  });

  final List<RsRegistryMember> members;
  final String searchQuery;
  final FanTier? filterTier;
  final bool isLoading;
  final bool hasMore;
  final int currentPage;

  static const _pageSize = 20;

  MemberRegistryState copyWith({
    List<RsRegistryMember>? members,
    String? searchQuery,
    FanTier? filterTier,
    bool clearFilter = false,
    bool? isLoading,
    bool? hasMore,
    int? currentPage,
  }) {
    return MemberRegistryState(
      members: members ?? this.members,
      searchQuery: searchQuery ?? this.searchQuery,
      filterTier: clearFilter ? null : (filterTier ?? this.filterTier),
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
    );
  }
}

class MemberRegistryNotifier extends StateNotifier<MemberRegistryState> {
  MemberRegistryNotifier(this._repository)
    : super(const MemberRegistryState()) {
    unawaited(_load());
  }

  final RayonSportsRepository _repository;
  Timer? _debounce;

  void search(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      state = state.copyWith(
        searchQuery: query,
        currentPage: 0,
        members: [],
        hasMore: true,
      );
      _load();
    });
  }

  void filterByTier(FanTier? tier) {
    state = state.copyWith(
      filterTier: tier,
      clearFilter: tier == null,
      currentPage: 0,
      members: [],
      hasMore: true,
    );
    unawaited(_load());
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;
    await _load(append: true);
  }

  Future<void> refresh() async {
    state = state.copyWith(currentPage: 0, members: [], hasMore: true);
    await _load();
  }

  Future<void> _load({bool append = false}) async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true);

    try {
      final page = append ? state.currentPage + 1 : 0;
      final offset = page * MemberRegistryState._pageSize;

      final partnerId = await _repository.getRayonPartnerId() ?? '';
      final result = await _repository.getMembers(
        partnerId,
        searchQuery: state.searchQuery.isEmpty ? null : state.searchQuery,
        filterTier: state.filterTier,
        limit: MemberRegistryState._pageSize,
        offset: offset,
      );

      final updatedMembers = append ? [...state.members, ...result] : result;

      state = state.copyWith(
        members: updatedMembers,
        currentPage: page,
        hasMore: result.length >= MemberRegistryState._pageSize,
        isLoading: false,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final memberRegistryProvider =
    StateNotifierProvider.autoDispose<
      MemberRegistryNotifier,
      MemberRegistryState
    >((ref) {
      final repo = ref.watch(rayonSportsRepositoryProvider);
      return MemberRegistryNotifier(repo);
    });

// ─────────────────────────────────────────────────────────────────────
// Fan Clubs
// ─────────────────────────────────────────────────────────────────────

@immutable
class FanClubsState {
  const FanClubsState({
    this.clubs = const [],
    this.myClub,
    this.filterRegion,
    this.isLoading = false,
  });

  final List<RsFanClub> clubs;
  final RsFanClub? myClub;
  final String? filterRegion;
  final bool isLoading;

  FanClubsState copyWith({
    List<RsFanClub>? clubs,
    RsFanClub? myClub,
    bool clearMyClub = false,
    String? filterRegion,
    bool clearRegion = false,
    bool? isLoading,
  }) {
    return FanClubsState(
      clubs: clubs ?? this.clubs,
      myClub: clearMyClub ? null : (myClub ?? this.myClub),
      filterRegion: clearRegion ? null : (filterRegion ?? this.filterRegion),
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class FanClubsNotifier extends StateNotifier<FanClubsState> {
  FanClubsNotifier(this._repository, this._userId)
    : super(const FanClubsState()) {
    unawaited(_load());
  }

  final RayonSportsRepository _repository;
  final String? _userId;

  void filterByRegion(String? region) {
    state = state.copyWith(
      filterRegion: region,
      clearRegion: region == null || region.isEmpty,
    );
    unawaited(_load());
  }

  Future<void> joinClub(String clubId) async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) return;

    await _repository.joinClub(clubId: clubId, userId: userId);

    // Award 200 points for first club join
    final partnerId = await _repository.getRayonPartnerId() ?? '';
    try {
      await _repository.addPoints(userId, partnerId, 200, 'first_club_join');
    } catch (_) {
      // Non-critical
    }

    await _load();
  }

  Future<void> leaveClub(String clubId) async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) return;
    await _repository.leaveClub(clubId: clubId, userId: userId);
    await _load();
  }

  Future<void> _load() async {
    state = state.copyWith(isLoading: true);
    try {
      final partnerId = await _repository.getRayonPartnerId() ?? '';
      final clubs = await _repository.getFanClubs(
        partnerId,
        state.filterRegion,
      );
      state = state.copyWith(clubs: clubs, isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }
}

final fanClubsProvider =
    StateNotifierProvider.autoDispose<FanClubsNotifier, FanClubsState>((ref) {
      final repo = ref.watch(rayonSportsRepositoryProvider);
      final authState = ref.watch(authProvider);
      final userId = authState.user?.id ?? authState.session?.user.id;
      return FanClubsNotifier(repo, userId);
    });

// ─────────────────────────────────────────────────────────────────────
// Matches
// ─────────────────────────────────────────────────────────────────────

final matchesProvider = FutureProvider.autoDispose<List<RsMatch>>((ref) async {
  final repo = ref.watch(rayonSportsRepositoryProvider);
  final partnerId = await ref.watch(rsPartnerIdProvider.future);
  return repo.getMatches(partnerId, false);
});

final onSaleMatchesProvider = FutureProvider.autoDispose<List<RsMatch>>((
  ref,
) async {
  final repo = ref.watch(rayonSportsRepositoryProvider);
  final partnerId = await ref.watch(rsPartnerIdProvider.future);
  return repo.getMatches(partnerId, true);
});

// ─────────────────────────────────────────────────────────────────────
// Tickets
// ─────────────────────────────────────────────────────────────────────

@immutable
class TicketsState {
  const TicketsState({
    this.isProcessing = false,
    this.lastTicketId,
    this.error,
  });

  final bool isProcessing;
  final String? lastTicketId;
  final String? error;

  TicketsState copyWith({
    bool? isProcessing,
    String? lastTicketId,
    String? error,
    bool clearError = false,
  }) {
    return TicketsState(
      isProcessing: isProcessing ?? this.isProcessing,
      lastTicketId: lastTicketId ?? this.lastTicketId,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class TicketsNotifier extends StateNotifier<TicketsState> {
  TicketsNotifier(this._repository, this._userId) : super(const TicketsState());

  final RayonSportsRepository _repository;
  final String? _userId;

  Future<List<RsTicket>> purchaseTicket({
    required RsMatch match,
    required String seatType,
    required int quantity,
  }) async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) {
      throw StateError('Sign in to purchase tickets.');
    }

    state = state.copyWith(isProcessing: true, clearError: true);

    try {
      final tickets = await _repository.purchaseTickets(
        matchId: match.id,
        userId: userId,
        seatType: seatType,
        quantity: quantity,
      );

      state = state.copyWith(
        isProcessing: false,
        lastTicketId: tickets.isNotEmpty ? tickets.first.id : null,
      );

      return tickets;
    } catch (e) {
      state = state.copyWith(isProcessing: false, error: e.toString());
      rethrow;
    }
  }
}

final ticketsNotifierProvider =
    StateNotifierProvider.autoDispose<TicketsNotifier, TicketsState>((ref) {
      final repo = ref.watch(rayonSportsRepositoryProvider);
      final authState = ref.watch(authProvider);
      final userId = authState.user?.id ?? authState.session?.user.id;
      return TicketsNotifier(repo, userId);
    });

final myTicketsProvider = FutureProvider.autoDispose
    .family<List<RsTicket>, String>((ref, userId) {
      final repo = ref.watch(rayonSportsRepositoryProvider);
      return repo.getMyTickets(userId);
    });

/// Cancel a pending ticket by ID.
Future<void> cancelTicketAction(WidgetRef ref, String ticketId) async {
  final repo = ref.read(rayonSportsRepositoryProvider);
  await repo.cancelTicket(ticketId);
}

/// Get all shop orders for a user.
final myOrdersProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, userId) {
      final repo = ref.watch(rayonSportsRepositoryProvider);
      return repo.getMyOrders(userId);
    });

/// Cancel a pending shop order by ID.
Future<void> cancelOrderAction(WidgetRef ref, String orderId) async {
  final repo = ref.read(rayonSportsRepositoryProvider);
  await repo.cancelOrder(orderId);
}

/// Get all clubs the current user has joined.
final userClubsProvider = FutureProvider.autoDispose
    .family<List<RsFanClub>, String>((ref, userId) {
      final repo = ref.watch(rayonSportsRepositoryProvider);
      return repo.getUserClubs(userId);
    });

// ─────────────────────────────────────────────────────────────────────
// Shop – Cart
// ─────────────────────────────────────────────────────────────────────

@immutable
class CartItem {
  const CartItem({required this.product, this.quantity = 1});

  final RsShopProduct product;
  final int quantity;

  int get lineTotal => product.price * quantity;

  CartItem copyWith({int? quantity}) {
    return CartItem(product: product, quantity: quantity ?? this.quantity);
  }
}

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super(const []);

  void addItem(RsShopProduct product, {int qty = 1}) {
    final idx = state.indexWhere((i) => i.product.id == product.id);
    if (idx >= 0) {
      final updated = [...state];
      updated[idx] = updated[idx].copyWith(
        quantity: updated[idx].quantity + qty,
      );
      state = updated;
    } else {
      state = [...state, CartItem(product: product, quantity: qty)];
    }
  }

  void removeItem(String productId) {
    state = state.where((i) => i.product.id != productId).toList();
  }

  void updateQty(String productId, int qty) {
    if (qty <= 0) {
      removeItem(productId);
      return;
    }
    final updated = state.map((i) {
      return i.product.id == productId ? i.copyWith(quantity: qty) : i;
    }).toList();
    state = updated;
  }

  void clear() => state = const [];

  // ── Computed getters ───────────────────────────────────────────────

  int get itemCount => state.fold<int>(0, (sum, item) => sum + item.quantity);

  int get subtotal => state.fold<int>(0, (sum, item) => sum + item.lineTotal);

  int discountedTotal(double discountPct) {
    if (discountPct <= 0) return subtotal;
    return (subtotal * (1 - discountPct / 100)).round();
  }

  int get total => subtotal;
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>((ref) {
  return CartNotifier();
});

// ─────────────────────────────────────────────────────────────────────
// Shop – Products
// ─────────────────────────────────────────────────────────────────────

@immutable
class ShopState {
  const ShopState({
    this.products = const [],
    this.category,
    this.isLoading = false,
    this.isCheckingOut = false,
  });

  final List<RsShopProduct> products;
  final String? category;
  final bool isLoading;
  final bool isCheckingOut;

  ShopState copyWith({
    List<RsShopProduct>? products,
    String? category,
    bool clearCategory = false,
    bool? isLoading,
    bool? isCheckingOut,
  }) {
    return ShopState(
      products: products ?? this.products,
      category: clearCategory ? null : (category ?? this.category),
      isLoading: isLoading ?? this.isLoading,
      isCheckingOut: isCheckingOut ?? this.isCheckingOut,
    );
  }
}

class ShopNotifier extends StateNotifier<ShopState> {
  ShopNotifier(this._repository, this._userId) : super(const ShopState()) {
    unawaited(_loadProducts());
  }

  final RayonSportsRepository _repository;
  final String? _userId;

  void filterByCategory(String? category) {
    state = state.copyWith(
      category: category,
      clearCategory: category == null || category.isEmpty,
    );
    unawaited(_loadProducts());
  }

  Future<String> placeOrder({
    required List<CartItem> cart,
    required String address,
    double discountPct = 0,
  }) async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) {
      throw StateError('Sign in to place an order.');
    }
    if (cart.isEmpty) throw StateError('Cart is empty.');

    state = state.copyWith(isCheckingOut: true);

    try {
      final products = cart.map((i) => i.product).toList(growable: false);
      final quantities = <String, int>{
        for (final item in cart) item.product.id: item.quantity,
      };

      final subtotal = cart.fold<int>(0, (s, i) => s + i.lineTotal);
      final discountAmount = (subtotal * discountPct / 100).round();

      final orderId = await _repository.placeOrder(
        userId: userId,
        products: products,
        quantities: quantities,
        deliveryAddress: address,
        discountAmount: discountAmount,
      );

      // Points are awarded by the backend (parse-momo-sms) after
      // SMS payment confirmation — do NOT award client-side.

      state = state.copyWith(isCheckingOut: false);
      return orderId;
    } catch (e) {
      state = state.copyWith(isCheckingOut: false);
      rethrow;
    }
  }

  Future<void> _loadProducts() async {
    state = state.copyWith(isLoading: true);
    try {
      final partnerId = await _repository.getRayonPartnerId() ?? '';
      final products = await _repository.getProducts(partnerId, state.category);
      state = state.copyWith(products: products, isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }
}

final shopProvider = StateNotifierProvider.autoDispose<ShopNotifier, ShopState>(
  (ref) {
    final repo = ref.watch(rayonSportsRepositoryProvider);
    final authState = ref.watch(authProvider);
    final userId = authState.user?.id ?? authState.session?.user.id;
    return ShopNotifier(repo, userId);
  },
);

// ─────────────────────────────────────────────────────────────────────
// Initiatives
// ─────────────────────────────────────────────────────────────────────

final initiativesProvider = FutureProvider.autoDispose<List<RsInitiative>>((
  ref,
) async {
  final repo = ref.watch(rayonSportsRepositoryProvider);
  final partnerId = await ref.watch(rsPartnerIdProvider.future);
  return repo.getInitiatives(partnerId);
});

// ── Support Detail Notifier ──────────────────────────────────────────

@immutable
class SupportDetailState {
  const SupportDetailState({
    this.selectedAmount = 0,
    this.isContributing = false,
    this.contributionId,
    this.error,
  });

  final int selectedAmount;
  final bool isContributing;
  final String? contributionId;
  final String? error;

  SupportDetailState copyWith({
    int? selectedAmount,
    bool? isContributing,
    String? contributionId,
    String? error,
    bool clearError = false,
  }) {
    return SupportDetailState(
      selectedAmount: selectedAmount ?? this.selectedAmount,
      isContributing: isContributing ?? this.isContributing,
      contributionId: contributionId ?? this.contributionId,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class SupportDetailNotifier extends StateNotifier<SupportDetailState> {
  SupportDetailNotifier(this._repository, this._userId, this._initiativeId)
    : super(const SupportDetailState());

  final RayonSportsRepository _repository;
  final String? _userId;
  final String _initiativeId;

  void setAmount(int amount) {
    state = state.copyWith(selectedAmount: amount, clearError: true);
  }

  void setCustomAmount(int amount) {
    state = state.copyWith(selectedAmount: amount, clearError: true);
  }

  Future<String> contribute() async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) {
      throw StateError('Sign in to contribute.');
    }
    if (state.selectedAmount <= 0) {
      throw StateError('Select an amount first.');
    }

    state = state.copyWith(isContributing: true, clearError: true);

    try {
      final contributionId = await _repository.contribute(
        initiativeId: _initiativeId,
        userId: userId,
        amount: state.selectedAmount,
      );

      // Points are awarded by the backend (parse-momo-sms) after
      // SMS payment confirmation — do NOT award client-side.

      state = state.copyWith(
        isContributing: false,
        contributionId: contributionId,
      );
      return contributionId;
    } catch (e) {
      state = state.copyWith(isContributing: false, error: e.toString());
      rethrow;
    }
  }
}

final supportDetailProvider = StateNotifierProvider.autoDispose
    .family<SupportDetailNotifier, SupportDetailState, String>((
      ref,
      initiativeId,
    ) {
      final repo = ref.watch(rayonSportsRepositoryProvider);
      final authState = ref.watch(authProvider);
      final userId = authState.user?.id ?? authState.session?.user.id;
      return SupportDetailNotifier(repo, userId, initiativeId);
    });

final recentContributorsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, initiativeId) {
      final repo = ref.watch(rayonSportsRepositoryProvider);
      return repo.getRecentContributors(initiativeId, 10);
    });

// ─────────────────────────────────────────────────────────────────────
// Achievements
// ─────────────────────────────────────────────────────────────────────

final achievementsProvider = FutureProvider.autoDispose
    .family<List<RsAchievement>, String>((ref, userId) async {
      // Achievements are part of the main data load; reuse it
      final state = ref.watch(rayonSportsProvider);
      return state.data.whenOrNull(data: (d) => d.achievements) ?? const [];
    });
