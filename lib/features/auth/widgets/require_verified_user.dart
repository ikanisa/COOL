import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_user_contact.dart';
import '../providers/auth_provider.dart';
import '../screens/whatsapp_otp_screen.dart';

/// The only features that are allowed to require WhatsApp authentication.
enum WhatsAppProtectedFeature { faceRegistration, groupJoin, groupCreate }

/// Checks whether the current user has completed WhatsApp authentication.
///
/// If not verified, opens the WhatsApp OTP screen as a full-screen modal.
/// Returns `true` when the user is verified (either already or after
/// completing the OTP flow). Returns `false` when the user dismisses.
///
/// Only these features should call this helper:
/// - face registration
/// - join group
/// - create group
///
/// Usage:
/// ```dart
/// if (
///   !await requireVerifiedUser(
///     context,
///     ref,
///     feature: WhatsAppProtectedFeature.groupCreate,
///   )
/// ) {
///   return;
/// }
/// // proceed with protected action
/// ```
Future<bool> requireVerifiedUser(
  BuildContext context,
  WidgetRef ref, {
  required WhatsAppProtectedFeature feature,
}) async {
  assert(
    WhatsAppProtectedFeature.values.contains(feature),
    'Only approved WhatsApp-protected features may invoke this gate.',
  );
  final authState = ref.read(authProvider);
  final profilePhone = authState.user?.phone.trim() ?? '';
  final sessionPhone = authSessionPhone(authState.session)?.trim() ?? '';
  if (profilePhone.isNotEmpty || sessionPhone.isNotEmpty) {
    return true;
  }

  // Show OTP verification screen.
  final result = await WhatsAppOtpScreen.show(context);
  return result == true;
}

/// Whether the current user is phone-verified.
bool isUserVerified(WidgetRef ref) {
  final authState = ref.read(authProvider);
  final profilePhone = authState.user?.phone.trim() ?? '';
  final sessionPhone = authSessionPhone(authState.session)?.trim() ?? '';
  return profilePhone.isNotEmpty || sessionPhone.isNotEmpty;
}
