part of 'collect_repository.dart';

// JWT claims here distinguish local lifecycle operations only; server Auth/RLS
// remains authoritative. Access-token fallback keeps malformed/legacy sessions
// isolated; such tokens do not bypass the server's required session_id check.
typedef _CollectAuthIdentity = ({String userId, String sessionId});
typedef _CollectSessionFence = ({
  _CollectAuthIdentity? identity,
  String? accessToken,
  int generation,
});
_CollectAuthIdentity? _sessionIdentity(CollectAuthSession? session) {
  if (session == null) return null;
  var identity = session.accessToken;
  try {
    final parts = session.accessToken.split('.');
    if (parts.length == 3) {
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (claims is Map &&
          claims['session_id'] is String &&
          (claims['session_id'] as String).isNotEmpty) {
        identity = claims['session_id'] as String;
      }
    }
  } catch (_) {
    // Do not expose token contents in exceptions or diagnostics.
  }
  return (userId: session.user.id, sessionId: identity);
}
