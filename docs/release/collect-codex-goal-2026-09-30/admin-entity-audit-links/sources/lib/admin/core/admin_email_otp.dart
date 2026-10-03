/// The Admin operator uses an existing, approved email account. This does not
/// change the member phone-authentication contract or create a user.
String normalizeAdminEmail(String value) {
  final email = value.trim().toLowerCase();
  if (email.length > 254 ||
      RegExp(r'[\s\u0000-\u001F\u007F]').hasMatch(email)) {
    throw const FormatException('Admin email is invalid.');
  }
  final parts = email.split('@');
  if (parts.length != 2 ||
      parts.first.isEmpty ||
      parts.first.length > 64 ||
      parts.first.startsWith('.') ||
      parts.first.endsWith('.') ||
      parts.first.contains('..') ||
      !RegExp(r"^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+$").hasMatch(parts.first)) {
    throw const FormatException('Admin email is invalid.');
  }
  final domain = parts.last.split('.');
  if (domain.length < 2 ||
      domain.any(
        (label) =>
            label.isEmpty ||
            label.length > 63 ||
            !RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(label),
      )) {
    throw const FormatException('Admin email is invalid.');
  }
  return email;
}

String normalizeAdminEmailOtp(String value) {
  final token = value.trim();
  if (!RegExp(r'^[0-9]{6}$').hasMatch(token)) {
    throw const FormatException('Admin email OTP must contain six digits.');
  }
  return token;
}
