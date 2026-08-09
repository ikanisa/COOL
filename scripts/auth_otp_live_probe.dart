import 'dart:convert';
import 'dart:io';

// This release probe intentionally uses the pure-Dart client pulled in by the
// app's pinned supabase_flutter dependency so it can run without a device.
// ignore: depend_on_referenced_packages
import 'package:supabase/supabase.dart';

String _requiredEnvironment(String name) {
  final value = Platform.environment[name]?.trim() ?? '';
  if (value.isEmpty) {
    throw StateError('$name is required.');
  }
  return value;
}

String _redact(String value, String phone) {
  return value
      .replaceAll(phone, '[PHONE]')
      .replaceAll(RegExp(r'eyJ[A-Za-z0-9._-]+'), '[TOKEN]')
      .replaceAll(RegExp(r'\+?\d{6,}'), '[REDACTED]');
}

Future<void> main() async {
  final supabaseUrl = _requiredEnvironment('SUPABASE_URL');
  final publishableKey = _requiredEnvironment('SUPABASE_ANON_KEY');
  final phone = _requiredEnvironment('COLLECT_AUTH_TEST_PHONE');
  final client = SupabaseClient(supabaseUrl, publishableKey);

  try {
    await client.auth.signInWithOtp(phone: phone, channel: OtpChannel.whatsapp);
    stdout.writeln(jsonEncode({'status': 'pass', 'channel': 'whatsapp'}));
  } catch (error) {
    stdout.writeln(
      jsonEncode({
        'status': 'fail',
        'error_type': error.runtimeType.toString(),
        'message': _redact(error.toString(), phone),
      }),
    );
    exitCode = 1;
  } finally {
    client.dispose();
  }
}
