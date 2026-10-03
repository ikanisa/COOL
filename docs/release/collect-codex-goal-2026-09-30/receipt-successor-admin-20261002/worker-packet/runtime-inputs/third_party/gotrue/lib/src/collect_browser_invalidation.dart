import 'dart:convert';

import 'package:gotrue/src/types/session.dart';

/// This is a denial notification, never a session or an authentication proof.
/// Tokens, user objects and refresh credentials must not cross the channel.
abstract final class CollectBrowserInvalidation {
  static const protocol = 'collect.auth.departed-session';
  static const version = 1;
  static const lifetimeSeconds = 30;
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static const _keys = {
    'protocol',
    'version',
    'event',
    'project',
    'actor',
    'session',
    'issued',
    'expires',
  };

  static String project(String url) {
    final uri = Uri.parse(url);
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    ).toString().replaceFirst(RegExp(r'/+$'), '');
  }

  static ({String actor, String session})? owner(Session? session) {
    if (session == null || !_uuid.hasMatch(session.user.id)) return null;
    try {
      final parts = session.accessToken.split('.');
      if (parts.length != 3 || parts[1].length > 8192) return null;
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (claims is! Map ||
          claims['sub'] != session.user.id ||
          claims['session_id'] is! String ||
          !_uuid.hasMatch(claims['session_id'] as String)) {
        return null;
      }
      return (actor: session.user.id, session: claims['session_id'] as String);
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? departed(
    Session? session,
    String url, {
    DateTime? now,
  }) {
    final identity = owner(session);
    if (identity == null) return null;
    final issued = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    return {
      'protocol': protocol,
      'version': version,
      'event': 'SIGNED_OUT',
      'project': project(url),
      'actor': identity.actor,
      'session': identity.session,
      'issued': issued,
      'expires': issued + lifetimeSeconds,
    };
  }

  static bool matchesOwner(Map<String, dynamic> message, Session? session) {
    final identity = owner(session);
    return identity != null &&
        message['actor'] == identity.actor &&
        message['session'] == identity.session;
  }

  static bool accepts(
    Map<String, dynamic> message,
    Session? session,
    String url, {
    DateTime? now,
  }) {
    if (message.length != _keys.length ||
        !message.keys.every(_keys.contains) ||
        message['protocol'] != protocol ||
        message['version'] != version ||
        message['event'] != 'SIGNED_OUT' ||
        message['project'] != project(url) ||
        message['actor'] is! String ||
        message['session'] is! String ||
        !_uuid.hasMatch(message['actor'] as String) ||
        !_uuid.hasMatch(message['session'] as String) ||
        message['issued'] is! int ||
        message['expires'] is! int) {
      return false;
    }
    final clock = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    final issued = message['issued'] as int;
    final expires = message['expires'] as int;
    return issued <= clock &&
        expires > clock &&
        expires - issued == lifetimeSeconds &&
        matchesOwner(message, session);
  }
}
