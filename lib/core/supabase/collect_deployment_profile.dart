import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Public, source-reviewed deployment identity. The digest binds configuration;
/// it is not a signature, an approval, or authority supplied by a server reply.
final class CollectDeploymentProfile {
  CollectDeploymentProfile._(this.values, this.sha256Digest);

  static const fields = <String>{
    'format',
    'id',
    'mode',
    'environment',
    'supabase_origin',
    'member_api_origin',
    'admin_origin',
    'public_origin',
    'google_callback_origin',
  };

  final Map<String, String> values;
  final String sha256Digest;
  String get id => values['id']!;
  String get mode => values['mode']!;
  String get environment => values['environment']!;
  String get supabaseOrigin => values['supabase_origin']!;
  String get memberApiOrigin => values['member_api_origin']!;
  String get adminOrigin => values['admin_origin']!;
  String get publicOrigin => values['public_origin']!;
  String get googleCallbackOrigin => values['google_callback_origin']!;

  static CollectDeploymentProfile? parse(String encoded, String digest) {
    if (encoded.isEmpty && digest.isEmpty) return null;
    try {
      if (encoded.isEmpty ||
          encoded.length > 8192 ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
        throw const FormatException();
      }
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic> ||
          decoded.length != fields.length ||
          decoded.keys.any((key) => !fields.contains(key)) ||
          decoded.values.any((value) => value is! String)) {
        throw const FormatException();
      }
      // A flat string map is the entire contract. Inspect source key tokens so
      // duplicate/escaped aliases cannot be interpreted differently by clients.
      final keys = RegExp(r'"(?:[^"\\]|\\.)*"\s*:').allMatches(encoded).map((
        match,
      ) {
        final token = match.group(0)!;
        return jsonDecode(token.substring(0, token.lastIndexOf(':')).trim());
      }).toList();
      if (keys.length != fields.length || keys.toSet().length != keys.length) {
        throw const FormatException();
      }
      final ordered = <String, String>{
        for (final key in decoded.keys.toList()..sort())
          key: decoded[key] as String,
      };
      if (encoded != jsonEncode(ordered) ||
          sha256.convert(utf8.encode(jsonEncode(ordered))).toString() !=
              digest ||
          ordered['format'] != 'collect.deployment.v1' ||
          !RegExp(r'^[a-z][a-z0-9-]{0,62}$').hasMatch(ordered['id']!) ||
          !const {'self_hosted', 'managed'}.contains(ordered['mode']) ||
          !const {
            'production',
            'qualification',
          }.contains(ordered['environment'])) {
        throw const FormatException();
      }
      for (final key in fields.where((key) => key.endsWith('_origin'))) {
        final value = ordered[key]!;
        final uri = Uri.parse(value);
        if (uri.scheme != 'https' ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty ||
            uri.hasQuery ||
            uri.hasFragment ||
            uri.path.isNotEmpty ||
            uri.port != 443 ||
            !_releaseHost(uri.host) ||
            uri.origin != value) {
          throw const FormatException();
        }
      }
      if (ordered['mode'] == 'managed' &&
          ordered['supabase_origin'] !=
              'https://rrlduytparvsjfmegalh.supabase.co') {
        throw const FormatException();
      }
      if (!{
        ordered['member_api_origin'],
        ordered['admin_origin'],
      }.contains(ordered['google_callback_origin'])) {
        throw const FormatException();
      }
      return CollectDeploymentProfile._(Map.unmodifiable(ordered), digest);
    } catch (_) {
      // Configuration might contain an accidentally supplied private value.
      // Never include the input, parser exception or calculated digest here.
      throw ArgumentError('The Collect deployment profile is invalid.');
    }
  }

  static bool _releaseHost(String host) {
    if (host.length > 253 || !host.contains('.') || host.endsWith('.')) {
      return false;
    }
    final labels = host.split('.');
    if (labels.any(
      (label) =>
          !RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$').hasMatch(label),
    )) {
      return false;
    }
    if (RegExp(r'^[0-9.]+$').hasMatch(host)) return false;
    return true;
  }
}
