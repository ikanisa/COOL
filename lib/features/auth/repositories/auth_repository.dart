import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';

class AuthRepository {
  AuthRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Session? get currentSession => _client.auth.currentSession;
  String? get currentUserId => _client.auth.currentUser?.id;

  Future<void> sendOtp(String phone, String language) async {
    final response = await _client.functions.invoke(
      'send-otp',
      body: <String, dynamic>{'phone': phone, 'language': language},
    );

    final data = _asMap(response.data);
    if (data['success'] == false) {
      throw StateError(data['message']?.toString() ?? 'Failed to send OTP.');
    }
  }

  Future<Session> verifyOtp(String phone, String code) async {
    final response = await _client.functions.invoke(
      'verify-otp',
      body: <String, dynamic>{'phone': phone, 'code': code},
    );

    final data = _asMap(response.data);
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
        .insert(profile.toJson())
        .select()
        .single();

    final created = UserProfile.fromJson(_asMap(inserted));
    await _persistProfileMetadata(created);
    return created;
  }

  Future<UserProfile> updateProfile(UserProfile profile) async {
    final data = profile.toJson();
    data.remove('id');
    data.remove('created_at');

    final updated = await _client
        .from('users')
        .update(data)
        .eq('id', profile.id)
        .select()
        .single();

    final result = UserProfile.fromJson(_asMap(updated));
    await _persistProfileMetadata(result);
    return result;
  }

  /// Partial update: only touches momo_number, momo_code, momo_provider.
  /// Prevents the full-profile upsert from writing privileged fields like
  /// is_admin back into the DB (audit fix P0 #3).
  Future<UserProfile> updateMomoInfo(
    String userId, {
    required String momoNumber,
    String? momoCode,
    required String momoProvider,
  }) async {
    final patch = <String, dynamic>{
      'momo_number': momoNumber,
      'momo_code': momoCode,
      'momo_provider': momoProvider,
    };
    patch.removeWhere((_, v) => v == null);

    final updated = await _client
        .from('users')
        .update(patch)
        .eq('id', userId)
        .select()
        .single();

    final result = UserProfile.fromJson(_asMap(updated));
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
      return UserProfile.fromJson(_asMap(data));
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
      body: <String, dynamic>{'confirm': true},
    );

    final data = _asMap(response.data);
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
          ...Map<String, dynamic>.from(currentUser.userMetadata ?? const {}),
          'phone': profile.phone,
          'full_name': profile.fullName,
          'momo_number': profile.momoNumber,
          'momo_code': profile.momoCode,
          'momo_provider': profile.momoProvider,
          'country': profile.country,
          'language_code': profile.languageCode,
          'is_driver': profile.isDriver,
          'vehicle_type': profile.vehicleType,
          'official_name': profile.officialName ?? profile.fullName,
          'official_phone': profile.officialPhone ?? profile.phone,
          'kyc_status': profile.kycStatus,
          'credit_consent_granted_at': profile.creditConsentGrantedAt
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

    final metadata = Map<String, dynamic>.from(user.userMetadata ?? const {});
    final phone =
        metadata['phone']?.toString() ??
        metadata['whatsapp_number']?.toString() ??
        user.phone ??
        '';

    if (phone.isEmpty && metadata.isEmpty) {
      return null;
    }

    return UserProfile.fromJson(<String, dynamic>{
      'id': user.id,
      'phone': phone,
      'full_name':
          metadata['full_name']?.toString() ??
          metadata['name']?.toString() ??
          '',
      'momo_number': metadata['momo_number']?.toString() ?? '',
      'momo_code': metadata['momo_code']?.toString(),
      'momo_provider': metadata['momo_provider']?.toString() ?? '',
      'country': metadata['country']?.toString() ?? '',
      'language_code': metadata['language_code']?.toString() ?? 'en',
      'is_driver': _asBool(metadata['is_driver']),
      'vehicle_type': metadata['vehicle_type']?.toString(),
      'official_name': metadata['official_name']?.toString(),
      'official_phone': metadata['official_phone']?.toString(),
      'kyc_status': metadata['kyc_status']?.toString() ?? 'unverified',
      'credit_consent_granted_at': metadata['credit_consent_granted_at'],
    });
  }
}

Map<String, dynamic> normalizeAuthSessionPayload(
  Map<String, dynamic> response,
) {
  final rawSession = _nestedMap(response, 'session') ?? response;
  final rawUser =
      _nestedMap(rawSession, 'user') ??
      _nestedMap(response, 'user') ??
      const {};

  return <String, dynamic>{
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
    'user': <String, dynamic>{
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
      'is_anonymous': _asBool(rawUser['is_anonymous']),
    }..removeWhere((_, value) => value == null),
  }..removeWhere((_, value) => value == null);
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  throw StateError('Expected a JSON object but received ${value.runtimeType}.');
}

Map<String, dynamic>? _nestedMap(Map<String, dynamic> root, String key) {
  final value = root[key];
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return null;
}

bool _asBool(dynamic value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.toLowerCase().trim();
    return normalized == 'true' || normalized == '1';
  }
  return false;
}

String? _stringOrNull(dynamic value) {
  if (value == null) {
    return null;
  }
  return value.toString();
}

int? _intOrNull(dynamic value) {
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

Map<String, dynamic>? _mapOrNull(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return null;
}

Map<String, dynamic> _mapOrEmpty(dynamic value) {
  return _mapOrNull(value) ?? <String, dynamic>{};
}
