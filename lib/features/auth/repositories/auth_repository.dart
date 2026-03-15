import 'dart:convert';

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

  Future<void> sendOtp(String phone, String language) async {
    assert(
      language.trim().isEmpty ||
          language.trim().toLowerCase() == AppMarket.languageCode,
      'COOL is English-only.',
    );
    final response = await _client.functions.invoke(
      'send-otp',
      body: <String, Object?>{
        'phone': phone,
        'language': AppMarket.languageCode,
      },
    );

    final data = jh.asMap(response.data);
    if (data['success'] == false) {
      throw StateError(data['message']?.toString() ?? 'Failed to send OTP.');
    }
  }

  Future<Session> verifyOtp(String phone, String code) async {
    final response = await _client.functions.invoke(
      'verify-otp',
      body: <String, Object?>{'phone': phone, 'code': code},
    );

    final data = jh.asMap(response.data);
    if (data['success'] == false) {
      throw StateError(data['message']?.toString() ?? 'Failed to verify OTP.');
    }

    final sessionPayload = normalizeAuthSessionPayload(data);
    final session = Session.fromJson(sessionPayload);
    if (session == null) {
      throw StateError('OTP verification did not return a valid session.');
    }

    final authResponse = await _client.auth.recoverSession(
      jsonEncode(sessionPayload),
    );
    return authResponse.session ?? session;
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
          'is_driver': profile.isDriver,
          'vehicle_type': profile.vehicleType,
          'avatar_url': profile.avatarUrl,
          'official_name': profile.officialName,
          'official_phone': profile.officialPhone,
          'kyc_status': profile.kycStatus,
          'kyc_verified_at': profile.kycVerifiedAt?.toIso8601String(),
          'credit_consent_granted_at': profile.creditConsentGrantedAt
              ?.toIso8601String(),
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
        'is_driver': jh.asBool(metadata['is_driver']),
        'vehicle_type': metadata['vehicle_type']?.toString(),
        'avatar_url': metadata['avatar_url']?.toString(),
        'official_name': metadata['official_name']?.toString(),
        'official_phone': metadata['official_phone']?.toString(),
        'kyc_status': metadata['kyc_status']?.toString() ?? 'unverified',
        'kyc_verified_at': metadata['kyc_verified_at'],
        'credit_consent_granted_at': metadata['credit_consent_granted_at'],
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

jh.JsonMap normalizeAuthSessionPayload(jh.JsonMap response) {
  final rawSession = _nestedMap(response, 'session') ?? response;
  final rawUser =
      _nestedMap(rawSession, 'user') ??
      _nestedMap(response, 'user') ??
      const <String, Object?>{};

  return <String, Object?>{
    'access_token':
        _stringOrNull(rawSession['access_token']) ??
        _stringOrNull(response['access_token']),
    'expires_in':
        _intOrNull(rawSession['expires_in']) ??
        _intOrNull(response['expires_in']),
    'refresh_token':
        _stringOrNull(rawSession['refresh_token']) ??
        _stringOrNull(response['refresh_token']),
    'token_type': _stringOrNull(rawSession['token_type']) ?? 'bearer',
    'provider_token': _stringOrNull(rawSession['provider_token']),
    'provider_refresh_token': _stringOrNull(
      rawSession['provider_refresh_token'],
    ),
    'user': <String, Object?>{
      'id': _stringOrNull(rawUser['id']) ?? '',
      'app_metadata': _mapOrEmpty(rawUser['app_metadata']),
      'user_metadata': _mapOrNull(rawUser['user_metadata']),
      'aud': _stringOrNull(rawUser['aud']) ?? '',
      'confirmation_sent_at': _stringOrNull(rawUser['confirmation_sent_at']),
      'recovery_sent_at': _stringOrNull(rawUser['recovery_sent_at']),
      'email_change_sent_at': _stringOrNull(rawUser['email_change_sent_at']),
      'new_email': _stringOrNull(rawUser['new_email']),
      'invited_at': _stringOrNull(rawUser['invited_at']),
      'action_link': _stringOrNull(rawUser['action_link']),
      'email': _stringOrNull(rawUser['email']),
      'phone': _stringOrNull(rawUser['phone']),
      'created_at': _stringOrNull(rawUser['created_at']) ?? '',
      'confirmed_at': _stringOrNull(rawUser['confirmed_at']),
      'email_confirmed_at': _stringOrNull(rawUser['email_confirmed_at']),
      'phone_confirmed_at': _stringOrNull(rawUser['phone_confirmed_at']),
      'last_sign_in_at': _stringOrNull(rawUser['last_sign_in_at']),
      'role': _stringOrNull(rawUser['role']),
      'updated_at': _stringOrNull(rawUser['updated_at']),
      'is_anonymous': jh.asBool(rawUser['is_anonymous']),
    }..removeWhere((_, value) => value == null),
  }..removeWhere((_, value) => value == null);
}

jh.JsonMap? _nestedMap(jh.JsonMap root, String key) {
  final value = root[key];
  if (value is jh.JsonMap) {
    return value;
  }
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  return null;
}

String? _stringOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  return value.toString();
}

int? _intOrNull(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

jh.JsonMap? _mapOrNull(Object? value) {
  if (value is jh.JsonMap) {
    return value;
  }
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  return null;
}

jh.JsonMap _mapOrEmpty(Object? value) {
  return _mapOrNull(value) ?? <String, Object?>{};
}
