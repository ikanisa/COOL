import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/rs_models.dart';
import '../repositories/rayon_sports_repository.dart';
import 'rayon_sports_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Member Registry — filter, search, paginate the fan directory
// ═══════════════════════════════════════════════════════════════════════════

enum MemberRegistryFilter {
  all('All'),
  fan('Fan'),
  bronze('Bronze'),
  gold('Gold'),
  platinum('Platinum');

  const MemberRegistryFilter(this.label);

  final String label;

  FanTier? get tier => switch (this) {
    MemberRegistryFilter.all => null,
    MemberRegistryFilter.fan => FanTier.fan,
    MemberRegistryFilter.bronze => FanTier.bronze,
    MemberRegistryFilter.gold => FanTier.gold,
    MemberRegistryFilter.platinum => FanTier.platinum,
  };
}

class MemberRegistryState {
  const MemberRegistryState({
    this.members = const <RsRegistryMember>[],
    this.topFan,
    this.filter = MemberRegistryFilter.all,
    this.query = '',
    this.isLoading = false,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.error,
  });

  final List<RsRegistryMember> members;
  final RsRegistryMember? topFan;
  final MemberRegistryFilter filter;
  final String query;
  final bool isLoading;
  final bool hasMore;
  final bool isLoadingMore;
  final String? error;

  MemberRegistryState copyWith({
    List<RsRegistryMember>? members,
    RsRegistryMember? topFan,
    bool clearTopFan = false,
    MemberRegistryFilter? filter,
    String? query,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    bool clearError = false,
  }) {
    return MemberRegistryState(
      members: members ?? this.members,
      topFan: clearTopFan ? null : (topFan ?? this.topFan),
      filter: filter ?? this.filter,
      query: query ?? this.query,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final memberRegistryProvider =
    StateNotifierProvider<MemberRegistryNotifier, MemberRegistryState>((ref) {
      final repository = ref.watch(rayonSportsRepositoryProvider);
      return MemberRegistryNotifier(repository: repository);
    });

class MemberRegistryNotifier extends StateNotifier<MemberRegistryState> {
  MemberRegistryNotifier({required this.repository})
      : super(const MemberRegistryState());

  final RayonSportsRepository repository;
  String? _partnerId;

  static const _pageSize = 20;

  void init(String partnerId) {
    _partnerId = partnerId;
    _load(reset: true);
  }

  void search(String query) {
    state = state.copyWith(query: query);
    _load(reset: true);
  }

  void selectFilter(MemberRegistryFilter filter) {
    state = state.copyWith(filter: filter);
    _load(reset: true);
  }

  Future<void> loadMore() => _load(reset: false);

  Future<void> _load({required bool reset}) async {
    final partnerId = _partnerId;
    if (partnerId == null || partnerId.isEmpty) return;

    if (reset) {
      state = state.copyWith(
        isLoading: true,
        members: const <RsRegistryMember>[],
        clearTopFan: true,
        clearError: true,
      );
    } else {
      state = state.copyWith(isLoading: true, clearError: true);
    }

    try {
      final offset = reset ? 0 : state.members.length;
      final members = await repository.getMembers(
        partnerId,
        searchQuery: state.query.trim().isEmpty ? null : state.query.trim(),
        filterTier: state.filter.tier,
        limit: _pageSize,
        offset: offset,
      );

      final allMembers = reset
          ? members
          : [...state.members, ...members];

      // First member with most points is the top fan
      RsRegistryMember? topFan;
      if (reset && allMembers.isNotEmpty && state.filter == MemberRegistryFilter.all) {
        topFan = allMembers.first;
      }

      if (!mounted) return;
      state = state.copyWith(
        members: allMembers,
        topFan: topFan,
        isLoading: false,
        hasMore: members.length >= _pageSize,
      );
    } catch (error) {
      debugPrint('[MemberRegistry] Load error: $error');
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load members. Tap to retry.',
      );
    }
  }
}
