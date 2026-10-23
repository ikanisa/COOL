import 'dart:convert';

enum CollectAuthEvent {
  initialSession,
  signedIn,
  signedOut,
  tokenRefreshed,
  userUpdated,
  mfaChallengeVerified,
}

enum CollectOtpType { sms, email }

enum CollectOtpChannel { whatsapp }

enum CollectSignOutScope { local, global }

enum CollectSyncStatus { connected, disconnected }

enum CollectFactorType { totp }

enum CollectFactorStatus { verified, unverified }

final class CollectAuthFactor {
  const CollectAuthFactor({
    required this.id,
    required this.factorType,
    required this.status,
  });
  final String id;
  final CollectFactorType factorType;
  final CollectFactorStatus status;
}

/// Collect-owned account data. It never asserts a server authorization level.
final class CollectAuthUser {
  const CollectAuthUser({
    required this.id,
    this.appMetadata = const {},
    this.userMetadata = const {},
    this.aud = 'authenticated',
    this.createdAt = '',
    this.email,
    this.phone,
    this.role,
    this.isAnonymous = false,
    this.factors,
    this.authUserId,
  });
  final String id;
  final Map<String, dynamic> appMetadata;
  final Map<String, dynamic>? userMetadata;
  final String aud;
  final String createdAt;
  final String? email;
  final String? phone;
  final String? role;
  final bool isAnonymous;
  final List<CollectAuthFactor>? factors;

  /// Supabase identity ID; [id] remains the stable Collect application principal.
  final String? authUserId;

  static CollectAuthUser? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$',
        ).hasMatch(id)) {
      return null;
    }
    Map<String, dynamic> metadata(Object? value) {
      if (value == null) return const {};
      if (value is! Map || value.keys.any((key) => key is! String)) {
        throw const FormatException();
      }
      return Map<String, dynamic>.unmodifiable(
        Map<String, dynamic>.from(value),
      );
    }

    final rawFactors = json['factors'];
    final authUserId = json['auth_user_id'];
    if (authUserId != null &&
        (authUserId is! String ||
            !RegExp(
              r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$',
            ).hasMatch(authUserId))) {
      throw const FormatException();
    }
    if (rawFactors != null && (rawFactors is! List || rawFactors.length > 20)) {
      throw const FormatException();
    }
    return CollectAuthUser(
      id: id,
      appMetadata: metadata(json['app_metadata']),
      userMetadata: metadata(json['user_metadata']),
      aud: json['aud'] as String? ?? 'authenticated',
      createdAt: json['created_at'] as String? ?? '',
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      role: json['role'] as String?,
      isAnonymous: json['is_anonymous'] == true,
      factors: rawFactors == null
          ? null
          : List.unmodifiable([
              for (final row in rawFactors as List)
                if (row is Map<String, dynamic> &&
                    row['id'] is String &&
                    row['factor_type'] == 'totp')
                  CollectAuthFactor(
                    id: row['id'] as String,
                    factorType: CollectFactorType.totp,
                    status: row['status'] == 'verified'
                        ? CollectFactorStatus.verified
                        : CollectFactorStatus.unverified,
                  ),
            ]),
      authUserId: authUserId as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'app_metadata': appMetadata,
    'user_metadata': userMetadata,
    'aud': aud,
    'created_at': createdAt,
    'email': email,
    'phone': phone,
    'role': role,
    'is_anonymous': isAnonymous,
    if (authUserId != null) 'auth_user_id': authUserId,
    if (factors != null)
      'factors': [
        for (final factor in factors!)
          {
            'id': factor.id,
            'factor_type': factor.factorType.name,
            'status': factor.status.name,
          },
      ],
  };
  @override
  String toString() => 'CollectAuthUser';
}

/// Only the server can verify these credentials. JWT decoding here is a local
/// ownership/expiry fence and is never used to grant a role or financial access.
final class CollectAuthSession {
  const CollectAuthSession({
    required this.accessToken,
    required this.user,
    this.refreshToken,
    this.expiresIn,
    this.expiresAt,
    this.tokenType = 'bearer',
    this.usesMappedAuthUser = false,
  });
  final String accessToken;
  final String? refreshToken;
  final int? expiresIn;
  final int? expiresAt;
  final String tokenType;
  final CollectAuthUser user;
  final bool usesMappedAuthUser;
  String get authSubject =>
      usesMappedAuthUser ? user.authUserId ?? user.id : user.id;

  Map<String, dynamic> get claims {
    try {
      final parts = accessToken.split('.');
      if (parts.length != 3 || accessToken.length > 32768) return const {};
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }

  bool get isExpired {
    final expiration = claims['exp'];
    return expiration is! int ||
        expiration <= DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  static CollectAuthSession? fromJson(
    Map<String, dynamic> json, {
    bool allowMappedAuthUser = false,
    String? expectedIssuer,
  }) {
    final rawUser = json['user'];
    final access = json['access_token'];
    final refresh = json['refresh_token'];
    if (rawUser is! Map<String, dynamic> ||
        access is! String ||
        access.isEmpty ||
        access.length > 32768 ||
        (refresh != null &&
            (refresh is! String ||
                refresh.isEmpty ||
                refresh.length > 32768))) {
      return null;
    }
    final user = CollectAuthUser.fromJson(rawUser);
    if (user == null) return null;
    final session = CollectAuthSession(
      accessToken: access,
      user: user,
      refreshToken: refresh as String?,
      expiresIn: json['expires_in'] as int?,
      expiresAt: json['expires_at'] as int?,
      tokenType: json['token_type'] as String? ?? 'bearer',
      usesMappedAuthUser: allowMappedAuthUser,
    );
    final claims = session.claims;
    final tokenOwner = allowMappedAuthUser
        ? user.authUserId ?? user.id
        : user.id;
    if (claims['sub'] != tokenOwner ||
        (expectedIssuer != null &&
            (claims['iss'] != expectedIssuer ||
                claims['aud'] != 'authenticated')) ||
        claims['session_id'] is! String ||
        (claims['session_id'] as String).isEmpty ||
        claims['role'] != 'authenticated' ||
        claims['exp'] is! int ||
        (claims['exp'] as int) > 253402300799 ||
        session.tokenType.toLowerCase() != 'bearer' ||
        user.isAnonymous) {
      return null;
    }
    return session;
  }

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'expires_in': expiresIn,
    'expires_at': expiresAt,
    'token_type': tokenType,
    'user': user.toJson(),
  };
  @override
  String toString() => 'CollectAuthSession';
}

final class CollectAuthState {
  const CollectAuthState(this.event, this.session);
  final CollectAuthEvent event;
  final CollectAuthSession? session;
  @override
  String toString() => 'CollectAuthState(${event.name})';
}

final class CollectAuthResponse {
  const CollectAuthResponse({this.session});
  final CollectAuthSession? session;
  CollectAuthUser? get user => session?.user;
}

class CollectApiException implements Exception {
  const CollectApiException({
    this.message = 'Collect could not complete this request.',
    this.code,
    this.details,
    this.hint,
  });
  final String message;
  final String? code;
  final Object? details;
  final String? hint;
  @override
  String toString() => 'CollectApiException(${code ?? 'unavailable'})';
}

class CollectAuthException implements Exception {
  const CollectAuthException(this.message, {this.statusCode, this.code});
  final String message;
  final String? statusCode;
  final String? code;
  @override
  String toString() =>
      'CollectAuthException(${code ?? statusCode ?? 'unavailable'})';
}

/// A recorded OTP request; this does not assert delivery to the recipient.
final class CollectOtpRequestReceipt {
  const CollectOtpRequestReceipt({required this.retryAfterSeconds});
  final int retryAfterSeconds;
}

/// The server retained a challenge, but provider delivery was not confirmed.
/// Keep the challenge private and let a code that arrives be verified once.
final class CollectOtpDeliveryUnknownException extends CollectAuthException {
  const CollectOtpDeliveryUnknownException({required this.retryAfterSeconds})
    : super(
        'Delivery could not be confirmed. If a code arrives, enter it here before requesting another.',
        statusCode: '503',
        code: 'otp_delivery_unknown',
      );
  final int retryAfterSeconds;
}

final class CollectFunctionResponse {
  const CollectFunctionResponse({required this.data, required this.status});
  final dynamic data;
  final int status;
}

class CollectFunctionException implements Exception {
  const CollectFunctionException({
    required this.status,
    this.details,
    this.reasonPhrase,
  });
  final int status;
  final Object? details;
  final String? reasonPhrase;
  @override
  String toString() => 'CollectFunctionException($status)';
}
