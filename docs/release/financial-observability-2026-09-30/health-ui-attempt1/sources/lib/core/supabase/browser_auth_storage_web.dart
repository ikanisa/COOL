import 'package:web/web.dart' as web;

/// Delete only the SDK keys owned by this configured project. Reading back
/// prevents silently continuing if browser storage blocks cleanup.
Future<void> removeOwnedLegacyBrowserCredentials(String supabaseUrl) async {
  final project = Uri.parse(supabaseUrl).host.split('.').first;
  final keys = <String>{
    'sb-$project-auth-token',
    'flutter.sb-$project-auth-token',
    'supabase.auth.token-code-verifier',
    'flutter.supabase.auth.token-code-verifier',
  };
  try {
    for (final storage in [web.window.localStorage, web.window.sessionStorage]) {
      for (final key in keys) {
        storage.removeItem(key);
        if (storage.getItem(key) != null) throw StateError('cleanup_failed');
      }
    }
  } catch (_) {
    throw StateError('Browser sign-in requires removal of previous saved Auth credentials.');
  }
}
