import 'package:flutter_contacts/flutter_contacts.dart' hide PermissionStatus;
import 'package:permission_handler/permission_handler.dart';

/// Lightweight service that wraps [FlutterContacts] with permission handling.
///
/// Returns contacts with phone numbers only — no emails, addresses, etc.
class ContactsService {
  const ContactsService();

  /// Request contacts permission.
  ///
  /// Returns the resulting [PermissionStatus].
  Future<PermissionStatus> requestPermission() async {
    final status = await Permission.contacts.request();
    return status;
  }

  /// Check if contacts permission is currently granted.
  Future<bool> get hasPermission async {
    return Permission.contacts.isGranted;
  }

  /// Fetch all contacts that have at least one phone number.
  ///
  /// Returns an empty list if permission is denied.
  Future<List<SimpleContact>> fetchContacts() async {
    final granted = await hasPermission;
    if (!granted) return const [];

    final contacts = await FlutterContacts.getAll(
      properties: {ContactProperty.phone},
    );

    return contacts
        .where((c) => c.phones.isNotEmpty)
        .map(
          (c) => SimpleContact(
            id: c.id ?? '',
            displayName: (c.displayName ?? '').trim().isNotEmpty
                ? c.displayName!.trim()
                : c.phones.first.number,
            phones: c.phones.map((p) => p.number).toList(),
          ),
        )
        .toList();
  }

  /// Search contacts locally by name or phone number.
  Future<List<SimpleContact>> searchContacts(
    String query, {
    List<SimpleContact>? cachedContacts,
  }) async {
    final contacts = cachedContacts ?? await fetchContacts();
    if (query.trim().isEmpty) return contacts;

    final q = query.trim().toLowerCase();
    return contacts.where((c) {
      if (c.displayName.toLowerCase().contains(q)) return true;
      return c.phones.any(
        (p) => p.replaceAll(RegExp(r'[\s\-\(\)+]'), '').contains(q),
      );
    }).toList();
  }
}

/// Minimal contact model with display name and phone numbers.
class SimpleContact {
  const SimpleContact({
    required this.id,
    required this.displayName,
    required this.phones,
  });

  final String id;
  final String displayName;
  final List<String> phones;

  /// First letter of name for avatar initials.
  String get initials {
    final parts = displayName.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
    }
    return displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
  }
}
