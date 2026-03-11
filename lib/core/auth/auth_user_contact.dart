import 'package:supabase_flutter/supabase_flutter.dart';

String? authUserPhone(User? user) {
  if (user == null) {
    return null;
  }

  final metadata = Map<String, dynamic>.from(user.userMetadata ?? const {});
  for (final candidate in <String?>[
    user.phone,
    metadata['phone']?.toString(),
    metadata['whatsapp_number']?.toString(),
  ]) {
    final trimmed = candidate?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
  }

  return null;
}

String? authSessionPhone(Session? session) {
  return authUserPhone(session?.user);
}
