import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart' show Box;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/auth_user_contact.dart';
import '../config/app_market.dart';
import '../config/app_config_repository.dart';
import '../config/country_catalog.dart';
import '../models/momo_qr_payload.dart';
import '../repositories/supported_countries_repository.dart';
import '../sync/sync_engine.dart';
import 'crashlytics_service.dart';
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
///
/// Pending transactions are written to Supabase when possible and cached in
/// Hive when the app is offline or Supabase is unavailable.
class MomoService {
  MomoService({
    required SupabaseClient client,
    required Future<Box<dynamic>> Function(String name) openBox,
    SyncEngine? syncEngine,
    AppConfigRepository? appConfigRepository,
    SupportedCountriesRepository? supportedCountriesRepository,
  }) : _client = client,
       _openBox = openBox,
       _syncEngine = syncEngine,
       _appConfigRepository =
           appConfigRepository ?? AppConfigRepository(client: client),
       _supportedCountriesRepository =
           supportedCountriesRepository ?? SupportedCountriesRepository();

  final SupabaseClient _client;
  final Future<Box<dynamic>> Function(String name) _openBox;
  final SyncEngine? _syncEngine;
  final AppConfigRepository _appConfigRepository;
  final SupportedCountriesRepository _supportedCountriesRepository;

  static const motoTaxiPlan = SubscriptionPlan.moto;
  static const cabOtherPlan = SubscriptionPlan.cabOther;

  static const _pendingTransactionsTable = 'pending_transactions';
  static const _pendingTransactionsCacheBox = 'pending_transactions_cache';
  static const _syncDomain = 'momo_pending';

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

    await _recordPendingTransaction(<String, dynamic>{
      'recipient_momo': normalizedRecipient,
      'amount': amount,
      'reference': reference,
      'provider': country.providerId,
      'status': 'pending',
      'raw_payload': <String, dynamic>{
        'country_code': country.isoCode,
        'country_name': country.name,
        'currency_code': country.currencyCode,
        'currency_name': country.currencyName,
        'recipient_type': recipientType.name,
        'ussd_template': recipientType == MomoRecipientType.code
            ? country.momoCodeUssdTemplate
            : country.momoUssdTemplate,
      },
      'created_at': DateTime.now().toIso8601String(),
    });

    final encoded = Uri.encodeComponent(ussdCode);
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

    await initiatePayment(
      recipientMomo: recipientMomo,
      amount: plan.amountRwf,
      reference: reference,
      recipientType: MomoRecipientType.code,
      countryCode: country.isoCode,
      providerId: country.providerId,
    );
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

  Future<void> _recordPendingTransaction(Map<String, dynamic> payload) async {
    try {
      final userId = _client.auth.currentUser?.id;
      await _client.from(_pendingTransactionsTable).insert(<String, dynamic>{
        ...?userId == null ? null : <String, dynamic>{'user_id': userId},
        ...payload,
      });
      debugPrint(
        '[MoMo] Pending transaction recorded to Supabase: '
        'ref=${payload['reference']}',
      );
    } catch (e) {
      debugPrint('[MoMo] ⚠️ Supabase insert failed ($e), caching locally');
      if (_syncEngine != null) {
        await _syncEngine.enqueue(_syncDomain, payload);
      } else {
        final box = await _openBox(_pendingTransactionsCacheBox);
        await box.add(payload);
      }
    }
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
