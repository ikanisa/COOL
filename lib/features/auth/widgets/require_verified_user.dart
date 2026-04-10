import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../screens/whatsapp_otp_screen.dart';

/// Checks whether the current user has a verified phone number.
///
/// If not verified, opens the WhatsApp OTP screen as a full-screen modal.
/// Returns `true` when the user is verified (either already or after
/// completing the OTP flow). Returns `false` when the user dismisses.
///
/// Usage:
/// ```dart
/// if (!await requireVerifiedUser(context, ref)) return;
/// // proceed with protected action
/// ```
Future<bool> requireVerifiedUser(BuildContext context, WidgetRef ref) async {
  final user = ref.read(currentUserProvider);
  if (user != null && user.phone.trim().isNotEmpty) {
    return true; // Already verified.
  }

  // Show OTP verification screen.
  final result = await WhatsAppOtpScreen.show(context);
  return result == true;
}

/// Whether the current user is phone-verified.
bool isUserVerified(WidgetRef ref) {
  final user = ref.read(currentUserProvider);
  return user != null && user.phone.trim().isNotEmpty;
}
