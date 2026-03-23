import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_market.dart';
import '../../../core/config/country_catalog.dart';
import '../models/biopay_match_result.dart';
import '../models/biopay_payment_intent.dart';
import '../models/biopay_profile.dart';

class BiopayDialerService {
  const BiopayDialerService();

  String buildUssdCode({
    required MomoRecipientType routeType,
    required String recipientValue,
    CoolCountry? country,
  }) {
    final resolvedCountry = country ?? AppMarket.country;
    final recipient = switch (routeType) {
      MomoRecipientType.phoneNumber => resolvedCountry.normalizeLocalPhone(
        recipientValue,
      ),
      MomoRecipientType.code => resolvedCountry.normalizeMerchantCode(
        recipientValue,
      ),
    };

    return switch (routeType) {
      MomoRecipientType.phoneNumber => '*182*1*1*$recipient#',
      MomoRecipientType.code => '*182*8*1*$recipient#',
    };
  }

  Uri buildDialUri({
    required MomoRecipientType routeType,
    required String recipientValue,
    CoolCountry? country,
  }) {
    final ussd = buildUssdCode(
      routeType: routeType,
      recipientValue: recipientValue,
      country: country,
    );
    return Uri.parse('tel:${ussd.replaceAll('#', '%23')}');
  }

  Uri buildProfileDialUri(BiopayProfile profile) {
    return buildDialUri(
      routeType: profile.routeType,
      recipientValue: profile.recipientValue,
      country: profile.country,
    );
  }

  Future<bool> dialProfile(BiopayProfile profile) async {
    return dialUri(buildProfileDialUri(profile));
  }

  Future<bool> dialMatch(BiopayMatchResult result) async {
    final profile = result.profile;
    if (profile == null) {
      return false;
    }
    return dialProfile(profile);
  }

  /// Dial a server-issued payment intent using the precomputed USSD code.
  ///
  /// Returns false if the intent is expired or the dialer cannot be launched.
  Future<bool> dialIntent(BiopayPaymentIntent intent) async {
    if (intent.isExpired) {
      return false;
    }
    return dialUri(intent.dialUri);
  }

  Future<bool> dialUri(Uri uri) async {
    final canLaunch = await canLaunchUrl(uri);
    if (!canLaunch) {
      return false;
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
