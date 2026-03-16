import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/auth_user_contact.dart';
import '../config/app_market.dart';
import '../config/app_config_repository.dart';
import '../config/country_catalog.dart';
import '../models/momo_qr_payload.dart';
import '../repositories/supported_countries_repository.dart';
import 'app_review_service.dart';
import 'crashlytics_service.dart';
import 'hive_runtime.dart';
import 'performance_service.dart';

enum SubscriptionPlan { moto, cabOther }

extension SubscriptionPlanX on SubscriptionPlan {
  String get id => switch (this) {
    SubscriptionPlan.moto => 'moto',
    SubscriptionPlan.cabOther => 'cab_other',
  };

  String get displayName => switch (this) {
    SubscriptionPlan.moto => 'Moto Taxi',
    SubscriptionPlan.cabOther => 'Cab / Other',
  };

  int get amountRwf => switch (this) {
    SubscriptionPlan.moto => 6000,
    SubscriptionPlan.cabOther => 15000,
  };

  String get emoji => switch (this) {
    SubscriptionPlan.moto => '🛺',
    SubscriptionPlan.cabOther => '🚗',
  };
}

/// Mobile Money USSD gateway for bridge-style payments.
///
/// Most flows provide the destination recipient explicitly. Mobility
/// subscription payments read their recipient code from admin-managed
/// `app_config` instead of build-time env vars.
class MomoService {
  MomoService({
    required SupabaseClient client,
    OpenHiveBox<dynamic>? openBox,
    AppConfigRepository? appConfigRepository,
    SupportedCountriesRepository? supportedCountriesRepository,
    AppReviewService? appReviewService,
  }) : _client = client,
       _appConfigRepository =
           appConfigRepository ?? AppConfigRepository(client: client),
       _supportedCountriesRepository =
           supportedCountriesRepository ?? SupportedCountriesRepository(),
       _appReviewService = appReviewService;

  final SupabaseClient _client;
  final AppConfigRepository _appConfigRepository;
  final SupportedCountriesRepository _supportedCountriesRepository;
  final AppReviewService? _appReviewService;

  static const motoTaxiPlan = SubscriptionPlan.moto;
  static const cabOtherPlan = SubscriptionPlan.cabOther;

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

  Future<void> initiateSubscription({
    required String driverId,
    required SubscriptionPlan plan,
    String? countryCode,
    String? providerId,
  }) async {
    final country = await _resolveCountry(
      countryCode: countryCode,
      providerId: providerId,
    );
    final recipientMomo = await _appConfigRepository
        .getMobilitySubscriptionMomoCode(forceRefresh: true);
    if (recipientMomo == null) {
      throw const MomoConfigurationException(
        AppConfigKeys.mobilitySubscriptionMomoCode,
      );
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final reference = 'SUB-$driverId-$timestamp';
    final createdAt = DateTime.now().toIso8601String();

    await _client.from('driver_subscriptions').insert(<String, dynamic>{
      'driver_id': driverId,
      'plan': plan.id,
      'plan_id': plan.id,
      'plan_name': plan.displayName,
      'amount': plan.amountRwf,
      'amount_rwf': plan.amountRwf,
      'status': 'pending',
      'momo_reference': reference,
      'created_at': createdAt,
      'updated_at': createdAt,
    });

    try {
      await initiatePayment(
        recipientMomo: recipientMomo,
        amount: plan.amountRwf,
        reference: reference,
        recipientType: MomoRecipientType.code,
        countryCode: country.isoCode,
        providerId: country.providerId,
      );
    } catch (error) {
      final cancelledAt = DateTime.now().toIso8601String();
      try {
        await _client
            .from('driver_subscriptions')
            .update(<String, dynamic>{
              'status': 'cancelled',
              'cancelled_at': cancelledAt,
              'updated_at': cancelledAt,
            })
            .eq('driver_id', driverId)
            .eq('momo_reference', reference)
            .eq('status', 'pending');
      } catch (updateError) {
        debugPrint(
          '[MoMo] ⚠️ Failed to cancel subscription checkout after dialer failure: '
          '$updateError',
        );
        _crashlytics?.recordError(
          updateError,
          reason: 'momo_subscription_checkout_cancel_failed',
        );
      }
      rethrow;
    }
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

  Future<void> initiateSubscriptionUSSD(
    SubscriptionPlan plan, {
    required String driverId,
    String? countryCode,
    String? providerId,
  }) {
    return initiateSubscription(
      driverId: driverId,
      plan: plan,
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
