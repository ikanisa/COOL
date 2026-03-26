import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/auth_user_contact.dart';
import '../config/app_market.dart';
import '../config/country_catalog.dart';
import '../models/momo_qr_payload.dart';
import '../repositories/supported_countries_repository.dart';
import 'app_review_service.dart';
import 'crashlytics_service.dart';
import 'hive_runtime.dart';
import 'performance_service.dart';

/// Mobile Money USSD gateway for bridge-style payments.
class MomoService {
  MomoService({
    required SupabaseClient client,
    OpenHiveBox<dynamic>? openBox,
    SupportedCountriesRepository? supportedCountriesRepository,
    AppReviewService? appReviewService,
  }) : _client = client,
       _supportedCountriesRepository =
           supportedCountriesRepository ?? SupportedCountriesRepository(),
       _appReviewService = appReviewService;

  final SupabaseClient _client;
  final SupportedCountriesRepository _supportedCountriesRepository;
  final AppReviewService? _appReviewService;

  // Firebase services for observability (late-bound, no-op if unavailable).
  CrashlyticsService? _crashlytics;
  PerformanceService? _performance;

  /// Inject Firebase services for observability. Call once after app init.
  void setObservabilityServices({
    required CrashlyticsService crashlytics,
    required PerformanceService performance,
  }) {
    _crashlytics = crashlytics;
    _performance = performance;
  }

  Future<void> initiatePayment({
    required String recipientMomo,
    required int amount,
    required String reference,
    MomoRecipientType recipientType = MomoRecipientType.phoneNumber,
    String? countryCode,
    String? providerId,
  }) async {
    if (recipientMomo.trim().isEmpty) {
      throw const MomoConfigurationException('recipient_momo');
    }

    debugPrint(
      '[MoMo] initiatePayment: amount=$amount, ref=$reference, '
      'recipient=$recipientMomo',
    );

    _performance?.startTrace('momo_ussd_payment');
    _crashlytics?.log('momo: initiating payment amount=$amount ref=$reference');

    final country = await _resolveCountry(
      countryCode: countryCode,
      providerId: providerId,
    );
    final normalizedRecipient = switch (recipientType) {
      MomoRecipientType.phoneNumber => country.buildE164Phone(recipientMomo),
      MomoRecipientType.code => country.normalizeMerchantCode(recipientMomo),
    };
    final ussdCode = country.buildUssdCode(
      recipientMomo: normalizedRecipient,
      amount: amount,
      recipientType: recipientType,
    );

    // Android requires # to be encoded as %23 in tel: URIs, otherwise it is
    // treated as a URI fragment delimiter and silently stripped.
    final encoded = ussdCode.replaceAll('#', '%23');
    final launched = await launchUrl(
      Uri.parse('tel:$encoded'),
      mode: LaunchMode.externalApplication,
    );

    if (!launched) {
      debugPrint('[MoMo] ❌ Failed to launch USSD dialer for ref=$reference');
      _performance?.stopTrace(
        'momo_ussd_payment',
        attributes: {'error': 'dialer_failed'},
      );
      _crashlytics?.recordError(
        const MomoDialerException(),
        reason: 'momo_dialer_launch_failed',
      );
      throw const MomoDialerException();
    }

    _performance?.stopTrace(
      'momo_ussd_payment',
      attributes: {'country': country.isoCode, 'provider': country.providerId},
    );
    _crashlytics?.log('momo: USSD launched for ref=$reference');
    debugPrint('[MoMo] ✅ USSD launched for ref=$reference');

    // Strong success moment: request app review.
    unawaited(_appReviewService?.requestReview() ?? Future.value());
  }

  Future<void> initiatePaymentUSSD(
    int amount, {
    required String recipientMomo,
    String? reference,
    MomoRecipientType recipientType = MomoRecipientType.phoneNumber,
    String? countryCode,
    String? providerId,
  }) {
    final paymentReference =
        reference ?? 'PAY-${DateTime.now().millisecondsSinceEpoch}';

    return initiatePayment(
      recipientMomo: recipientMomo,
      amount: amount,
      reference: paymentReference,
      recipientType: recipientType,
      countryCode: countryCode,
      providerId: providerId,
    );
  }

  Future<void> initiateUSSD({
    required int amount,
    required String recipientMomo,
    String? reference,
    MomoRecipientType recipientType = MomoRecipientType.phoneNumber,
    String? countryCode,
    String? providerId,
  }) {
    return initiatePaymentUSSD(
      amount,
      recipientMomo: recipientMomo,
      reference: reference,
      recipientType: recipientType,
      countryCode: countryCode,
      providerId: providerId,
    );
  }

  String generateQrData(
    String recipientValue, {
    CoolCountry? country,
    MomoRecipientType recipientType = MomoRecipientType.phoneNumber,
    int? amount,
    String? reference,
    bool preferDirectDial = true,
  }) {
    if (country == null) {
      return 'momo://${recipientValue.replaceAll(RegExp(r'[^0-9+]'), '')}';
    }

    final normalizedRecipient = switch (recipientType) {
      MomoRecipientType.phoneNumber => country.buildE164Phone(recipientValue),
      MomoRecipientType.code => country.normalizeMerchantCode(recipientValue),
    };
    final payload = amount != null && amount > 0
        ? MomoQrPayload.paymentRequest(
            recipientValue: normalizedRecipient,
            recipientType: recipientType,
            amount: amount,
            countryCode: country.isoCode,
            reference: reference,
          )
        : MomoQrPayload.profile(
            recipientValue: normalizedRecipient,
            recipientType: recipientType,
            countryCode: country.isoCode,
            reference: reference,
          );
    return payload.toQrData(country, preferDirectDial: preferDirectDial);
  }

  Future<CoolCountry> resolveCountry({
    String? countryCode,
    String? providerId,
    String? phone,
  }) {
    return _resolveCountry(
      countryCode: countryCode,
      providerId: providerId,
      phone: phone,
    );
  }

  Future<CoolCountry> _resolveCountry({
    String? countryCode,
    String? providerId,
    String? phone,
  }) async {
    final currentUser = _client.auth.currentUser;
    final metadata = Map<String, dynamic>.from(
      currentUser?.userMetadata ?? const <String, dynamic>{},
    );

    return _supportedCountriesRepository.resolveCountry(
      countryCode: countryCode ?? AppMarket.countryCode,
      phone:
          phone ??
          metadata['momo_number']?.toString() ??
          metadata['phone']?.toString() ??
          authUserPhone(currentUser),
      providerId: providerId ?? metadata['momo_provider']?.toString(),
    );
  }
}

class MomoDialerException implements Exception {
  const MomoDialerException();
}

class MomoConfigurationException implements Exception {
  const MomoConfigurationException(this.keyName);

  final String keyName;
}
