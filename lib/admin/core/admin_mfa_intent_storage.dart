/// The short-lived recovery capability is scoped to one browser tab. It is
/// never an authenticator code, provider token, password or cookie value.
class AdminMfaRecoveryIntent {
  const AdminMfaRecoveryIntent({
    required this.factorId,
    required this.challengeId,
    required this.verificationId,
    required this.sessionId,
    required this.userId,
    required this.startingAssuranceLevel,
    required this.startingMfaAtMillis,
    required this.createdAtMillis,
  });

  final String factorId;
  final String challengeId;
  final String verificationId;
  final String sessionId;
  final String userId;
  final int startingAssuranceLevel;
  final int? startingMfaAtMillis;
  final int createdAtMillis;

  Map<String, Object?> toJson() => {
    'factor_id': factorId,
    'challenge_id': challengeId,
    'verification_id': verificationId,
    'session_id': sessionId,
    'user_id': userId,
    'starting_assurance_level': startingAssuranceLevel,
    'starting_mfa_at_ms': startingMfaAtMillis,
    'created_at_ms': createdAtMillis,
  };

  static AdminMfaRecoveryIntent parse(Object? value) {
    const keys = {
      'factor_id',
      'challenge_id',
      'verification_id',
      'session_id',
      'user_id',
      'starting_assurance_level',
      'starting_mfa_at_ms',
      'created_at_ms',
    };
    if (value is! Map ||
        value.length != keys.length ||
        !value.keys.every(keys.contains)) {
      throw const FormatException();
    }
    final factor = value['factor_id'];
    final challenge = value['challenge_id'];
    final verification = value['verification_id'];
    final session = value['session_id'];
    final user = value['user_id'];
    final assurance = value['starting_assurance_level'];
    final mfaAt = value['starting_mfa_at_ms'];
    final created = value['created_at_ms'];
    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    if (factor is! String ||
        !uuid.hasMatch(factor) ||
        challenge is! String ||
        !uuid.hasMatch(challenge) ||
        verification is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(verification) ||
        session is! String ||
        session.isEmpty ||
        session.length > 200 ||
        user is! String ||
        user.isEmpty ||
        user.length > 200 ||
        assurance is! int ||
        !{1, 2}.contains(assurance) ||
        (mfaAt != null && (mfaAt is! int || mfaAt <= 0)) ||
        (assurance == 2 && mfaAt == null) ||
        created is! int ||
        created <= 0) {
      throw const FormatException();
    }
    return AdminMfaRecoveryIntent(
      factorId: factor,
      challengeId: challenge,
      verificationId: verification,
      sessionId: session,
      userId: user,
      startingAssuranceLevel: assurance,
      startingMfaAtMillis: mfaAt as int?,
      createdAtMillis: created,
    );
  }
}

abstract interface class AdminMfaIntentStorage {
  AdminMfaRecoveryIntent? read();
  void write(AdminMfaRecoveryIntent intent);
  void clear();
}

class MemoryAdminMfaIntentStorage implements AdminMfaIntentStorage {
  AdminMfaRecoveryIntent? _value;
  @override
  AdminMfaRecoveryIntent? read() => _value;
  @override
  void write(AdminMfaRecoveryIntent intent) => _value = intent;
  @override
  void clear() => _value = null;
}
