import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../../../core/providers/supabase_client_provider.dart';
import '../../../core/config/country_catalog.dart';
import '../models/rs_contribution_models.dart';

// ═══════════════════════════════════════════════════════════
// Contribution Groups Providers
// ═══════════════════════════════════════════════════════════

/// Lists public & club contribution groups (visible to everyone).
final publicContributionGroupsProvider =
    FutureProvider.autoDispose<List<RsContributionGroup>>((ref) async {
      final client = ref.watch(supabaseClientProvider);
      final response = await client
          .from('contribution_groups')
          .select()
          .inFilter('privacy', ['public'])
          .eq('is_closed', false)
          .order('created_at', ascending: false);

      return (response as List)
          .map(
            (json) =>
                RsContributionGroup.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    });

/// Lists contribution groups where the current user is the creator.
final myContributionGroupsProvider =
    FutureProvider.autoDispose<List<RsContributionGroup>>((ref) async {
      final client = ref.watch(supabaseClientProvider);
      final authState = ref.watch(authProvider);
      final userId = authState.user?.id ?? authState.session?.user.id;
      if (userId == null) return [];

      final response = await client
          .from('contribution_groups')
          .select()
          .eq('creator_id', userId)
          .order('created_at', ascending: false);

      return (response as List)
          .map(
            (json) =>
                RsContributionGroup.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    });

/// Fetches a single contribution group by ID.
final contributionGroupDetailProvider = FutureProvider.autoDispose
    .family<RsContributionGroup?, String>((ref, groupId) async {
      final client = ref.watch(supabaseClientProvider);
      final response = await client
          .from('contribution_groups')
          .select()
          .eq('id', groupId)
          .maybeSingle();

      if (response == null) return null;
      return RsContributionGroup.fromJson(response);
    });

/// Fetches messages for a contribution group.
/// Uses a FutureProvider with manual refresh (simpler than Realtime for v1).
final groupMessagesProvider = FutureProvider.autoDispose
    .family<List<RsGroupMessage>, String>((ref, groupId) async {
      final client = ref.watch(supabaseClientProvider);
      final response = await client
          .from('group_messages')
          .select()
          .eq('group_id', groupId)
          .order('created_at', ascending: true)
          .limit(100);

      return (response as List)
          .map((json) => RsGroupMessage.fromJson(json as Map<String, dynamic>))
          .toList();
    });

// ═══════════════════════════════════════════════════════════
// Contribution Group CRUD Controller
// ═══════════════════════════════════════════════════════════

final contributionGroupControllerProvider =
    StateNotifierProvider<ContributionGroupController, AsyncValue<void>>((ref) {
      return ContributionGroupController(ref);
    });

class ContributionGroupController extends StateNotifier<AsyncValue<void>> {
  ContributionGroupController(this._ref) : super(const AsyncData(null));

  final Ref _ref;

  /// Create a new contribution group.
  Future<RsContributionGroup?> createGroup({
    required String name,
    String? description,
    required ContributionGroupType groupType,
    required GroupPrivacy privacy,
    required int targetAmount,
    String? momoNumber,
    String? momoCode,
    MomoRecipientType? momoRouteType,
    DateTime? deadline,
    bool isRecurring = false,
  }) async {
    state = const AsyncLoading();
    try {
      final client = _ref.read(supabaseClientProvider);
      final authState = _ref.read(authProvider);
      final userId = authState.user?.id ?? authState.session?.user.id;
      if (userId == null) throw Exception('Not authenticated');

      final normalizedNumber = momoNumber?.trim();
      final normalizedCode = momoCode?.trim();
      final effectiveRouteType =
          momoRouteType ??
          (normalizedNumber?.isNotEmpty == true
              ? MomoRecipientType.phoneNumber
              : normalizedCode?.isNotEmpty == true
              ? MomoRecipientType.code
              : null);
      final recipientValue = switch (effectiveRouteType) {
        MomoRecipientType.phoneNumber => normalizedNumber,
        MomoRecipientType.code => normalizedCode,
        null =>
          normalizedCode?.isNotEmpty == true
              ? normalizedCode
              : normalizedNumber,
      };

      final data = {
        'creator_id': userId,
        'name': name,
        'description': description,
        'group_type': groupType.value,
        'privacy': privacy.value,
        'target_amount': targetAmount,
        'momo_number': normalizedNumber,
        'receiving_momo_code': normalizedCode,
        'momo_route_type': switch (effectiveRouteType) {
          MomoRecipientType.phoneNumber => 'phone_number',
          MomoRecipientType.code => 'code',
          null => null,
        },
        'momo_code': recipientValue,
        'deadline': deadline?.toIso8601String(),
        'is_recurring': isRecurring,
      };

      final response = await client
          .from('contribution_groups')
          .insert(data)
          .select()
          .single();

      final group = RsContributionGroup.fromJson(response);

      // Invalidate lists
      _ref.invalidate(myContributionGroupsProvider);
      _ref.invalidate(publicContributionGroupsProvider);

      state = const AsyncData(null);
      return group;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }

  /// Send a message in a contribution group.
  Future<bool> sendMessage({
    required String groupId,
    required String content,
  }) async {
    try {
      final client = _ref.read(supabaseClientProvider);
      await client.from('group_messages').insert({
        'group_id': groupId,
        'content': content,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Close a contribution group (creator only).
  Future<bool> closeGroup(String groupId) async {
    state = const AsyncLoading();
    try {
      final client = _ref.read(supabaseClientProvider);
      await client
          .from('contribution_groups')
          .update({'is_closed': true})
          .eq('id', groupId);

      _ref.invalidate(myContributionGroupsProvider);
      _ref.invalidate(publicContributionGroupsProvider);
      _ref.invalidate(contributionGroupDetailProvider(groupId));

      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}
