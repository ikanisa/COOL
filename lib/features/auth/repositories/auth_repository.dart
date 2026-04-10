import 'package:cool_app/core/utils/json_helpers.dart' as jh;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_market.dart';
import '../../../core/config/country_catalog.dart';
import '../models/user_profile.dart';

class AuthRepository {
  AuthRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  Session? get currentSession => _client.auth.currentSession;
  String? get currentUserId => _client.auth.currentUser?.id;

  /// Signs in anonymously via Supabase. Returns the new session.
  Future<Session> signInAnonymously() async {
    final response = await _client.auth.signInAnonymously();
    final session = response.session;
    if (session == null) {
      throw StateError('Anonymous sign-in did not return a valid session.');
    }
    return session;
  }

  /// Sets a session from access + refresh tokens (e.g. after OTP verification).
  Future<Session?> setSession({
    required String accessToken,
    required String refreshToken,
  }) async {
    final response = await _client.auth.setSession(refreshToken);
    return response.session;
  }

  Future<UserProfile> createProfile(UserProfile profile) async {
    final inserted = await _client
        .from('users')
        .insert(_lockProfileMarket(profile.toJson()))
        .select()
        .single();

    final created = UserProfile.fromJson(
      _lockProfileMarket(jh.asMap(inserted)),
    );
    await _persistProfileMetadata(created);
    return created;
  }

  Future<UserProfile> updateProfile(UserProfile profile) async {
    final data = _lockProfileMarket(profile.toJson());
    data.remove('id');
    data.remove('created_at');

    final updated = await _client
        .from('users')
        .update(data)
        .eq('id', profile.id)
        .select()
        .single();

    final result = UserProfile.fromJson(_lockProfileMarket(jh.asMap(updated)));
    await _persistProfileMetadata(result);
    return result;
  }

  /// Partial update: only touches wallet routing fields.
  /// Prevents the full-profile upsert from writing privileged fields like
  /// is_admin back into the DB (audit fix P0 #3).
  Future<UserProfile> updateMomoInfo(
    String userId, {
    required String momoNumber,
    String? momoCode,
    MomoRecipientType? momoRouteType,
    required String momoProvider,
    required String country,
  }) async {
    assert(
      country.trim().isEmpty ||
          country.trim().toUpperCase() == AppMarket.countryCode,
      'COOL is locked to the Rwanda market.',
    );
    final patch = <String, Object?>{
      'momo_number': momoNumber,
      'momo_code': momoCode,
      'momo_route_type': switch (momoRouteType) {
        MomoRecipientType.phoneNumber => 'phone_number',
        MomoRecipientType.code => 'code',
        null => null,
      },
      'momo_provider': momoProvider,
      'country': AppMarket.countryCode,
      'language_code': AppMarket.languageCode,
    };

    final updated = await _client
        .from('users')
        .update(patch)
        .eq('id', userId)
        .select()
        .single();

    final result = UserProfile.fromJson(_lockProfileMarket(jh.asMap(updated)));
    await _persistProfileMetadata(result);
    return result;
  }

  Future<UserProfile?> getProfile(String userId) async {
    final data = await _client
        .from('users')
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (data != null) {
      return UserProfile.fromJson(_lockProfileMarket(jh.asMap(data)));
    }

    return _profileFromMetadata(userId);
  }

  Future<UserProfile?> getCurrentProfile() async {
    final userId = currentUserId;
    if (userId == null) {
      return null;
    }
    return getProfile(userId);
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Future<void> deleteAccount() async {
    final response = await _client.functions.invoke(
      'delete-account',
      body: <String, Object?>{'confirm': true},
    );

    final data = jh.asMap(response.data);
    if (data['success'] != true) {
      throw StateError(
        data['message']?.toString() ?? 'Failed to delete account.',
      );
    }

    try {
      await _client.auth.signOut();
    } catch (_) {
      // The auth user may already be gone server-side.
    }
  }

  Future<void> _persistProfileMetadata(UserProfile profile) async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null || currentUser.id != profile.id) {
      return;
    }

    await _client.auth.updateUser(
      UserAttributes(
        data: <String, dynamic>{
          ...jh.asMap(currentUser.userMetadata),
          'public_user_id': profile.displayUserId,
          'phone': profile.phone,
          'full_name': profile.fullName,
          'momo_number': profile.momoNumber,
          'momo_code': profile.momoCode,
          'momo_route_type': switch (profile.effectiveMomoRouteType) {
            MomoRecipientType.phoneNumber => 'phone_number',
            MomoRecipientType.code => 'code',
            null => null,
          },
          'momo_provider': profile.momoProvider,
          'country': AppMarket.countryCode,
          'language_code': AppMarket.languageCode,
          'market': AppMarket.countryCode,
          'ui_language': AppMarket.languageCode,
          'avatar_url': profile.avatarUrl,
          'official_name': profile.officialName,
          'official_phone': profile.officialPhone,
          'theme_preference': profile.themePreference,
          'theme_preference_updated_at': profile.themePreferenceUpdatedAt
              ?.toIso8601String(),
        }..removeWhere((_, value) => value == null),
      ),
    );
  }

  UserProfile? _profileFromMetadata(String userId) {
    final user = _client.auth.currentUser;
    if (user == null || user.id != userId) {
      return null;
    }

    final metadata = jh.asMapOrEmpty(user.userMetadata);
    final phone =
        metadata['phone']?.toString() ??
        metadata['whatsapp_number']?.toString() ??
        user.phone ??
        '';

    if (phone.isEmpty && metadata.isEmpty) {
      return null;
    }

    return UserProfile.fromJson(
      _lockProfileMarket(<String, Object?>{
        'id': user.id,
        'public_user_id': metadata['public_user_id']?.toString(),
        'phone': phone,
        'full_name':
            metadata['full_name']?.toString() ??
            metadata['name']?.toString() ??
            '',
        'momo_number': metadata['momo_number']?.toString() ?? '',
        'momo_code': metadata['momo_code']?.toString(),
        'momo_route_type': metadata['momo_route_type']?.toString(),
        'momo_provider': metadata['momo_provider']?.toString() ?? '',
        'country': AppMarket.countryCode,
        'language_code': AppMarket.languageCode,
        'avatar_url': metadata['avatar_url']?.toString(),
        'official_name': metadata['official_name']?.toString(),
        'official_phone': metadata['official_phone']?.toString(),
        'theme_preference': metadata['theme_preference'],
        'theme_preference_updated_at': metadata['theme_preference_updated_at'],
      }),
    );
  }
}

Map<String, dynamic> _lockProfileMarket(Map<String, dynamic> data) {
  return <String, dynamic>{
    ...data,
    'country': AppMarket.countryCode,
    'language_code': AppMarket.languageCode,
  };
}
