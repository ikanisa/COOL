import '../../../core/config/country_catalog.dart' as market;
import '../../../core/services/momo_service.dart';
import '../../../core/services/operational_health_service.dart';
import '../rayon/models/rs_models.dart';
import '../rayon/rayon_payment.dart';

class RayonCheckoutResult<T> {
  const RayonCheckoutResult({
    required this.value,
    this.subjectType,
    this.subjectId,
    this.successMetadata = const <String, Object?>{},
  });

  final T value;
  final String? subjectType;
  final String? subjectId;
  final RsJsonMap successMetadata;
}

class RayonSportsCheckoutService {
  RayonSportsCheckoutService({
    required MomoService momoService,
    required OperationalHealthService operationalHealthService,
    required Future<PartnerPaymentRoute> Function({bool forceRefresh})
    getActivePaymentRoute,
  }) : _momoService = momoService,
       _operationalHealthService = operationalHealthService,
       _getActivePaymentRoute = getActivePaymentRoute;

  final MomoService _momoService;
  final OperationalHealthService _operationalHealthService;
  final Future<PartnerPaymentRoute> Function({bool forceRefresh})
  _getActivePaymentRoute;

  Future<T> openCheckout<T>({
    required String component,
    required String userId,
    required String referencePrefix,
    required int amount,
    required String successMessage,
    required String failureMessage,
    required RsJsonMap failureMetadata,
    required Future<RayonCheckoutResult<T>> Function(String reference) prepare,
  }) async {
    final paymentRoute = await _getActivePaymentRoute();
    final reference =
        '$referencePrefix-${DateTime.now().millisecondsSinceEpoch}';

    try {
      final result = await prepare(reference);
      await _momoService.initiateUSSD(
        amount: amount,
        reference: reference,
        countryCode: paymentRoute.countryCode,
        recipientMomo: paymentRoute.recipientCode,
        recipientType: market.MomoRecipientType.code,
      );
      await _operationalHealthService.recordEvent(
        service: 'partner_checkout',
        component: component,
        status: OperationalHealthStatus.ok,
        message: successMessage,
        userId: userId,
        subjectType: result.subjectType,
        subjectId: result.subjectId,
        metadata: <String, dynamic>{
          'reference': reference,
          ...result.successMetadata,
        },
      );
      return result.value;
    } catch (error) {
      await _operationalHealthService.recordEvent(
        service: 'partner_checkout',
        component: component,
        status: OperationalHealthStatus.error,
        issueCode: 'partner_checkout_failed',
        message: failureMessage,
        userId: userId,
        metadata: <String, dynamic>{
          'reference': reference,
          ...failureMetadata,
          'error': error.toString(),
        },
      );
      rethrow;
    }
  }
}
