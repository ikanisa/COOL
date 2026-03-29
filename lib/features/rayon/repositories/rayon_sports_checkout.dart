import '../../../core/services/momo_service.dart';
import '../../../core/services/operational_health_service.dart';
import '../rayon_payment.dart';

/// Result of a checkout flow — wraps both the domain value and metadata
/// needed for operational health tracking.
class RayonCheckoutResult<T> {
  const RayonCheckoutResult({
    required this.value,
    required this.subjectType,
    this.subjectId,
    this.successMetadata = const <String, Object?>{},
  });

  /// The domain-level value produced by the checkout (e.g. a ticket, order ID).
  final T value;

  /// Table / subject type for operational health records.
  final String subjectType;

  /// Optional subject record ID for health tracking.
  final String? subjectId;

  /// Additional metadata logged on success.
  final Map<String, Object?> successMetadata;
}

/// Orchestrates a checkout flow:
///   1. Generate a payment reference.
///   2. Run the [prepare] callback to create domain records.
///   3. Launch MoMo USSD for the user to complete payment.
///   4. Log operational health (success or failure).
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

  /// Opens a checkout flow. [prepare] receives the MoMo payment reference
  /// and must return a [RayonCheckoutResult] wrapping the domain value.
  Future<T> openCheckout<T>({
    required String component,
    required String userId,
    required String referencePrefix,
    required int amount,
    required String successMessage,
    required String failureMessage,
    Map<String, Object?> failureMetadata = const <String, Object?>{},
    required Future<RayonCheckoutResult<T>> Function(String paymentReference)
        prepare,
  }) async {
    final paymentRoute = await _getActivePaymentRoute(forceRefresh: false);
    final paymentReference =
        '$referencePrefix-${DateTime.now().millisecondsSinceEpoch}';

    try {
      // Create domain records first (tickets, order, contribution)
      final result = await prepare(paymentReference);

      // Fire the MoMo USSD prompt
      await _momoService.initiatePayment(
        recipientMomo: paymentRoute.recipientCode,
        amount: amount,
        reference: paymentReference,
      );

      // Log success via operational health
      await _operationalHealthService.recordEvent(
        service: 'rayon_sports',
        component: component,
        message: successMessage,
        status: OperationalHealthStatus.ok,
        userId: userId,
        subjectType: result.subjectType,
        subjectId: result.subjectId,
        metadata: result.successMetadata,
      );

      return result.value;
    } catch (error, _) {
      // Log failure via operational health
      await _operationalHealthService.recordEvent(
        service: 'rayon_sports',
        component: component,
        message: failureMessage,
        status: OperationalHealthStatus.error,
        userId: userId,
        subjectType: 'checkout_failure',
        metadata: <String, Object?>{
          ...failureMetadata,
          'error': '$error',
        },
      );
      rethrow;
    }
  }
}
