import 'admin_email_otp.dart';

/// Metadata received only from the authenticated, versioned Admin session.
/// Backend mutation guards remain authoritative for every owner action.
class AdminOwnerIdentity {
  const AdminOwnerIdentity._(this.adminId, this.principalId, this.email);

  final String adminId;
  final String principalId;
  final String email;
  (String, String, String) get authorityKey => (adminId, principalId, email);

  static bool validOpaqueId(Object? value) =>
      value is String &&
      value.isNotEmpty &&
      value.length <= 200 &&
      value == value.trim() &&
      !RegExp(r'[\u0000-\u001f\u007f-\u009f]').hasMatch(value);

  static AdminOwnerIdentity? parse(Object? value) {
    if (value is! Map ||
        value.length != 4 ||
        !const [
          'schemaVersion',
          'adminId',
          'principalId',
          'email',
        ].every(value.containsKey) ||
        value['schemaVersion'] is! int ||
        value['schemaVersion'] != 1 ||
        !validOpaqueId(value['adminId']) ||
        !validOpaqueId(value['principalId']) ||
        value['email'] is! String) {
      return null;
    }
    final email = value['email'] as String;
    try {
      if (normalizeAdminEmail(email) != email) return null;
      return AdminOwnerIdentity._(
        value['adminId'] as String,
        value['principalId'] as String,
        email,
      );
    } on FormatException {
      return null;
    }
  }

  bool matchesActor(String id, String? principal, String actorEmail) {
    return adminId == id && principalId == principal && email == actorEmail;
  }
}
