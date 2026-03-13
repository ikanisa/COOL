import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_market.dart';
import '../../../core/providers/supabase_client_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../momo/providers/momo_service_provider.dart';
import '../models/group.dart';
import '../models/group_contribution.dart';
import '../models/group_detail.dart';
import '../models/group_join_result.dart';
import '../repositories/group_repository.dart';

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return GroupRepository(
    client: ref.read(supabaseClientProvider),
    momoService: ref.read(momoServiceProvider),
  );
});

final groupDetailProvider = FutureProvider.autoDispose
    .family<GroupDetail?, String>((ref, groupId) async {
      final repository = ref.watch(groupRepositoryProvider);
      return repository.getGroupById(groupId, country: AppMarket.countryCode);
    });

final groupsProvider = StateNotifierProvider<GroupsNotifier, GroupsState>((
  ref,
) {
  final authState = ref.watch(authProvider);
  return GroupsNotifier(ref: ref, authState: authState);
});

final groupsListProvider = Provider<List<Group>>((ref) {
  return ref.watch(groupsProvider.select((state) => state.groups));
});

final groupsListLoadingProvider = Provider<bool>((ref) {
  return ref.watch(groupsProvider.select((state) => state.isLoading));
});

final groupsListErrorProvider = Provider<String?>((ref) {
  return ref.watch(groupsProvider.select((state) => state.error));
});

final groupsCreateLoadingProvider = Provider<bool>((ref) {
  return ref.watch(groupsProvider.select((state) => state.isCreatingGroup));
});

final groupsCreateErrorProvider = Provider<String?>((ref) {
  return ref.watch(groupsProvider.select((state) => state.createGroupError));
});

final groupInvitePreviewProvider = Provider<GroupDetail?>((ref) {
  return ref.watch(groupsProvider.select((state) => state.invitePreview));
});

final groupInvitePreviewLoadingProvider = Provider<bool>((ref) {
  return ref.watch(
    groupsProvider.select((state) => state.isInvitePreviewLoading),
  );
});

final groupInvitePreviewErrorProvider = Provider<String?>((ref) {
  return ref.watch(groupsProvider.select((state) => state.invitePreviewError));
});

final groupJoinLoadingProvider = Provider<bool>((ref) {
  return ref.watch(groupsProvider.select((state) => state.isJoiningGroup));
});

final groupJoinErrorProvider = Provider<String?>((ref) {
  return ref.watch(groupsProvider.select((state) => state.joinGroupError));
});

final groupContributionLoadingProvider = Provider<bool>((ref) {
  return ref.watch(groupsProvider.select((state) => state.isContributing));
});

final groupContributionErrorProvider = Provider<String?>((ref) {
  return ref.watch(groupsProvider.select((state) => state.contributionError));
});

class GroupsState {
  const GroupsState({
    this.groups = const <Group>[],
    this.invitePreview,
    this.isCreatingGroup = false,
    this.createGroupError,
    this.isInvitePreviewLoading = false,
    this.invitePreviewError,
    this.isJoiningGroup = false,
    this.joinGroupError,
    this.isContributing = false,
    this.contributionError,
    this.isLoading = false,
    this.error,
  });

  static const _sentinel = Object();

  final List<Group> groups;
  final GroupDetail? invitePreview;
  final bool isCreatingGroup;
  final String? createGroupError;
  final bool isInvitePreviewLoading;
  final String? invitePreviewError;
  final bool isJoiningGroup;
  final String? joinGroupError;
  final bool isContributing;
  final String? contributionError;
  final bool isLoading;
  final String? error;

  GroupsState copyWith({
    List<Group>? groups,
    Object? invitePreview = _sentinel,
    bool? isCreatingGroup,
    Object? createGroupError = _sentinel,
    bool? isInvitePreviewLoading,
    Object? invitePreviewError = _sentinel,
    bool? isJoiningGroup,
    Object? joinGroupError = _sentinel,
    bool? isContributing,
    Object? contributionError = _sentinel,
    bool? isLoading,
    Object? error = _sentinel,
  }) {
    return GroupsState(
      groups: groups ?? this.groups,
      invitePreview: invitePreview == _sentinel
          ? this.invitePreview
          : invitePreview as GroupDetail?,
      isCreatingGroup: isCreatingGroup ?? this.isCreatingGroup,
      createGroupError: createGroupError == _sentinel
          ? this.createGroupError
          : createGroupError as String?,
      isInvitePreviewLoading:
          isInvitePreviewLoading ?? this.isInvitePreviewLoading,
      invitePreviewError: invitePreviewError == _sentinel
          ? this.invitePreviewError
          : invitePreviewError as String?,
      isJoiningGroup: isJoiningGroup ?? this.isJoiningGroup,
      joinGroupError: joinGroupError == _sentinel
          ? this.joinGroupError
          : joinGroupError as String?,
      isContributing: isContributing ?? this.isContributing,
      contributionError: contributionError == _sentinel
          ? this.contributionError
          : contributionError as String?,
      isLoading: isLoading ?? this.isLoading,
      error: error == _sentinel ? this.error : error as String?,
    );
  }
}

class GroupCreateData {
  const GroupCreateData({
    required this.name,
    required this.type,
    required this.visibility,
    required this.targetAmountRwf,
    this.country,
    this.monthlyContributionRwf,
    this.bankPartner,
    this.momoNumber,
    this.momoRouteType,
    this.description,
    this.frequency = 'monthly',
    this.cycleDays = 30,
  });

  final String name;
  final String type;
  final String visibility;
  final int targetAmountRwf;
  final String? country;
  final int? monthlyContributionRwf;
  final String? bankPartner;
  final String? momoNumber;
  final String? momoRouteType;
  final String? description;
  final String frequency;
  final int cycleDays;
}

class GroupsNotifier extends StateNotifier<GroupsState> {
  GroupsNotifier({
    Ref? ref,
    GroupRepository? repository,
    required AuthState authState,
  }) : assert(ref != null || repository != null),
       _ref = ref,
       _repositoryOverride = repository,
       _authState = authState,
       super(const GroupsState());

  final Ref? _ref;
  final GroupRepository? _repositoryOverride;
  final AuthState _authState;

  GroupRepository get _repository =>
      _repositoryOverride ?? _ref!.read(groupRepositoryProvider);

  List<Group> _allGroups = const <Group>[];

  String? get currentError =>
      state.contributionError ??
      state.joinGroupError ??
      state.createGroupError ??
      state.invitePreviewError ??
      state.error;

  String? get _currentUserId =>
      _authState.user?.id ?? _authState.session?.user.id;

  String get _defaultCountry => AppMarket.countryCode;

  String get _viewerCountry => AppMarket.countryCode;

  Future<void> loadMyGroups() async {
    await _loadMyGroupsInternal();
  }

  Future<void> loadPublicGroups() async {
    state = state.copyWith(isLoading: true, error: null);

    final result = await AsyncValue.guard(
      () => _repository.getPublicGroups(_defaultCountry),
    );

    result.when(
      data: (groups) {
        _allGroups = groups;
        state = state.copyWith(groups: groups, isLoading: false, error: null);
      },
      error: (error, _) {
        state = state.copyWith(isLoading: false, error: error.toString());
      },
      loading: () {},
    );
  }

  Future<void> loadFilteredMyGroups({String? type, String? visibility}) async {
    await _loadMyGroupsInternal(type: type, visibility: visibility);
  }

  Future<void> _loadMyGroupsInternal({String? type, String? visibility}) async {
    final userId = _currentUserId;
    if (userId == null) {
      state = state.copyWith(
        groups: const <Group>[],
        isLoading: false,
        error: 'You must be signed in to load groups.',
      );
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    final result = await AsyncValue.guard(
      () => _repository.getMyGroups(userId, country: _viewerCountry),
    );

    result.when(
      data: (groups) {
        _allGroups = groups;
        state = state.copyWith(
          groups: _applyFilters(groups, type: type, visibility: visibility),
          isLoading: false,
          error: null,
        );
      },
      error: (error, _) {
        state = state.copyWith(isLoading: false, error: error.toString());
      },
      loading: () {},
    );
  }

  Future<void> loadInvitePreview(String inviteCode) async {
    state = state.copyWith(
      invitePreview: null,
      isInvitePreviewLoading: true,
      invitePreviewError: null,
    );

    final result = await AsyncValue.guard(
      () =>
          _repository.getGroupByInviteCode(inviteCode, country: _viewerCountry),
    );

    result.when(
      data: (groupDetail) {
        state = state.copyWith(
          invitePreview: groupDetail,
          isInvitePreviewLoading: false,
          invitePreviewError: groupDetail == null
              ? 'Invite code not found.'
              : null,
        );
      },
      error: (error, _) {
        state = state.copyWith(
          isInvitePreviewLoading: false,
          invitePreviewError: error.toString(),
        );
      },
      loading: () {},
    );
  }

  Future<Group?> createGroup(GroupCreateData data) async {
    final userId = _currentUserId;
    if (userId == null) {
      state = state.copyWith(
        isCreatingGroup: false,
        createGroupError: 'You must be signed in to create a group.',
      );
      return null;
    }

    state = state.copyWith(isCreatingGroup: true, createGroupError: null);

    final result = await AsyncValue.guard(
      () => _repository.createGroup(
        Group(
          creatorId: userId,
          name: data.name,
          type: _normalizeType(data.type) ?? 'saving',
          visibility: _normalizeVisibility(data.visibility) ?? 'private',
          amount: 0,
          targetAmount: data.targetAmountRwf,
          country: data.country ?? _defaultCountry,
          monthlyContribution: data.monthlyContributionRwf,
          description: data.description,
          bankPartner: data.bankPartner,
          momoNumber: data.momoNumber,
          momoRouteType: data.momoRouteType,
          frequency: data.frequency,
        ),
      ),
    );

    Group? createdGroup;

    result.when(
      data: (group) {
        createdGroup = group;
        _allGroups = <Group>[group, ..._allGroups];
        state = state.copyWith(
          groups: <Group>[group, ...state.groups],
          isCreatingGroup: false,
          createGroupError: null,
        );
      },
      error: (error, _) {
        state = state.copyWith(
          isCreatingGroup: false,
          createGroupError: error.toString(),
        );
      },
      loading: () {},
    );

    return createdGroup;
  }

  void clearCreateGroupState() {
    if (!state.isCreatingGroup && state.createGroupError == null) {
      return;
    }

    state = state.copyWith(isCreatingGroup: false, createGroupError: null);
  }

  void clearInvitePreviewState() {
    if (!state.isInvitePreviewLoading &&
        state.invitePreview == null &&
        state.invitePreviewError == null) {
      return;
    }

    state = state.copyWith(
      invitePreview: null,
      isInvitePreviewLoading: false,
      invitePreviewError: null,
    );
  }

  void clearJoinGroupState() {
    if (!state.isJoiningGroup && state.joinGroupError == null) {
      return;
    }

    state = state.copyWith(isJoiningGroup: false, joinGroupError: null);
  }

  void clearContributionState() {
    if (!state.isContributing && state.contributionError == null) {
      return;
    }

    state = state.copyWith(isContributing: false, contributionError: null);
  }

  Future<GroupContribution?> contribute(String groupId, int amount) async {
    final userId = _currentUserId;
    if (userId == null) {
      state = state.copyWith(
        isContributing: false,
        contributionError: 'You must be signed in to contribute to a group.',
      );
      return null;
    }

    state = state.copyWith(isContributing: true, contributionError: null);

    final result = await AsyncValue.guard(
      () => _repository.contribute(groupId, amount),
    );

    GroupContribution? contribution;

    result.when(
      data: (_) {
        final value = GroupContribution(
          groupId: groupId,
          userId: userId,
          amount: amount,
          status: 'pending',
          contributorName: _authState.user?.displayUserId,
          createdAt: DateTime.now(),
        );
        contribution = value;
        state = state.copyWith(isContributing: false, contributionError: null);
        unawaited(loadMyGroups());
      },
      error: (error, _) {
        state = state.copyWith(
          isContributing: false,
          contributionError: error.toString(),
        );
      },
      loading: () {},
    );

    return contribution;
  }

  Future<GroupJoinResult?> joinGroupByInviteCode(String inviteCode) async {
    final userId = _currentUserId;
    if (userId == null) {
      state = state.copyWith(
        isJoiningGroup: false,
        joinGroupError: 'You must be signed in to join a group.',
      );
      return null;
    }

    state = state.copyWith(isJoiningGroup: true, joinGroupError: null);

    final result = await AsyncValue.guard(
      () => _repository.joinGroupByInviteCode(
        inviteCode,
        country: _viewerCountry,
      ),
    );

    GroupJoinResult? joinResult;

    result.when(
      data: (value) {
        joinResult = value;
        final joinedGroup = value.detail.group;
        _allGroups = _upsertGroup(_allGroups, joinedGroup);
        state = state.copyWith(
          groups: _upsertGroup(state.groups, joinedGroup),
          invitePreview: value.detail,
          isJoiningGroup: false,
          joinGroupError: null,
        );
      },
      error: (error, _) {
        state = state.copyWith(
          isJoiningGroup: false,
          joinGroupError: error.toString(),
        );
      },
      loading: () {},
    );

    return joinResult;
  }

  void filterGroups(String? type, String? visibility) {
    final normalizedType = _normalizeType(type);
    final normalizedVisibility = _normalizeVisibility(visibility);
    state = state.copyWith(
      groups: _applyFilters(
        _allGroups,
        type: normalizedType,
        visibility: normalizedVisibility,
      ),
      error: null,
    );
  }

  List<Group> _applyFilters(
    List<Group> groups, {
    String? type,
    String? visibility,
  }) {
    final normalizedType = _normalizeType(type);
    final normalizedVisibility = _normalizeVisibility(visibility);

    return groups.where((group) {
      final matchesType =
          normalizedType == null || group.type.toLowerCase() == normalizedType;
      final matchesVisibility =
          normalizedVisibility == null ||
          group.visibility.toLowerCase() == normalizedVisibility;
      return matchesType && matchesVisibility;
    }).toList();
  }

  List<Group> _upsertGroup(List<Group> groups, Group group) {
    final groupId = group.id;
    if (groupId == null || groupId.isEmpty) {
      return groups;
    }

    final index = groups.indexWhere((item) => item.id == groupId);
    if (index == -1) {
      return <Group>[group, ...groups];
    }

    final updated = groups.toList(growable: true);
    updated[index] = group;
    return updated;
  }

  String? _normalizeType(String? value) {
    final normalized = value?.toLowerCase() ?? '';
    if (normalized.isEmpty || normalized == 'all') return null;
    if (normalized.contains('saving')) return 'saving';
    if (normalized.contains('community')) return 'community';
    return normalized;
  }

  String? _normalizeVisibility(String? value) {
    final normalized = value?.toLowerCase() ?? '';
    if (normalized.isEmpty || normalized == 'all') return null;
    if (normalized.contains('public')) return 'public';
    if (normalized.contains('private')) return 'private';
    return null;
  }
}
