import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rayon/models/rs_models.dart';
import '../repositories/rayon_sports_repository.dart';

const _registryPageSize = 20;

final memberRegistryProvider =
    StateNotifierProvider.autoDispose<
      MemberRegistryNotifier,
      MemberRegistryState
    >((ref) {
      final repository = ref.watch(
        Provider<RayonSportsRepository>((ref) => RayonSportsRepository()),
      );
      return MemberRegistryNotifier(repository: repository);
    });

enum MemberRegistryFilter { all, platinum, gold, silver, blue, kigali }

extension MemberRegistryFilterX on MemberRegistryFilter {
  String get label => switch (this) {
    MemberRegistryFilter.all => 'All Members',
    MemberRegistryFilter.platinum => '★ Platinum',
    MemberRegistryFilter.gold => 'Gold',
    MemberRegistryFilter.silver => 'Silver',
    MemberRegistryFilter.blue => 'Blue',
    MemberRegistryFilter.kigali => 'Kigali',
  };

  FanTier? get tier => switch (this) {
    MemberRegistryFilter.all => null,
    MemberRegistryFilter.platinum => FanTier.platinum,
    MemberRegistryFilter.gold => FanTier.gold,
    MemberRegistryFilter.silver => FanTier.silver,
    MemberRegistryFilter.blue => FanTier.blue,
    MemberRegistryFilter.kigali => null,
  };

  String? get region => switch (this) {
    MemberRegistryFilter.kigali => 'kigali',
    _ => null,
  };
}

class MemberRegistryState {
  const MemberRegistryState({
    this.query = '',
    this.filter = MemberRegistryFilter.all,
    this.members = const <RsRegistryMember>[],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.totalLoaded = 0,
    this.error,
  });

  final String query;
  final MemberRegistryFilter filter;
  final List<RsRegistryMember> members;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final int totalLoaded;
  final String? error;

  /// The top fan is the member with the most points.
  RsRegistryMember? get topFan {
    if (members.isEmpty) return null;
    return members.reduce(
      (best, candidate) => candidate.points > best.points ? candidate : best,
    );
  }

  MemberRegistryState copyWith({
    String? query,
    MemberRegistryFilter? filter,
    List<RsRegistryMember>? members,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    int? totalLoaded,
    String? error,
    bool clearError = false,
  }) {
    return MemberRegistryState(
      query: query ?? this.query,
      filter: filter ?? this.filter,
      members: members ?? this.members,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      totalLoaded: totalLoaded ?? this.totalLoaded,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class MemberRegistryNotifier extends StateNotifier<MemberRegistryState> {
  MemberRegistryNotifier({required RayonSportsRepository repository})
      : _repository = repository,
        super(const MemberRegistryState());

  final RayonSportsRepository _repository;
  String? _partnerId;

  /// Call once with the current partner ID to trigger the initial page load.
  Future<void> init(String partnerId) async {
    _partnerId = partnerId;
    await _fetchPage(reset: true);
  }

  void search(String query) {
    final trimmed = query.trimLeft();
    if (trimmed == state.query) return;
    state = state.copyWith(query: trimmed);
    _fetchPage(reset: true);
  }

  void selectFilter(MemberRegistryFilter filter) {
    if (filter == state.filter) return;
    state = state.copyWith(filter: filter);
    _fetchPage(reset: true);
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    await _fetchPage(reset: false);
  }

  Future<void> _fetchPage({required bool reset}) async {
    final partnerId = _partnerId;
    if (partnerId == null || partnerId.isEmpty) return;

    final offset = reset ? 0 : state.totalLoaded;

    state = state.copyWith(
      isLoading: reset,
      isLoadingMore: !reset,
      clearError: true,
    );

    try {
      final page = await _repository.getMembers(
        partnerId,
        searchQuery: state.query.isEmpty ? null : state.query,
        filterTier: state.filter.tier,
        region: state.filter.region,
        limit: _registryPageSize,
        offset: offset,
      );

      final newMembers = reset ? page : [...state.members, ...page];

      state = state.copyWith(
        members: newMembers,
        isLoading: false,
        isLoadingMore: false,
        hasMore: page.length >= _registryPageSize,
        totalLoaded: newMembers.length,
      );
    } catch (error, stack) {
      debugPrint('[MemberRegistry] ❌ fetchPage failed: $error');
      debugPrint('[MemberRegistry] $stack');
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        error: error.toString(),
      );
    }
  }
}
