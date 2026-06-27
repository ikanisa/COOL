part of 'collect_repository.dart';

class CollectState {
  const CollectState({
    required this.currentProfile,
    required this.collections,
    required this.paymentIntents,
    required this.contributions,
    this.notificationEvents = const [],
    this.notificationPreferences = NotificationPreferences.defaults,
    this.smsAccessEnabled = false,
    this.smsAccessDenied = false,
    this.isLoading = false,
    this.lastError,
  });

  final CollectProfile? currentProfile;
  final List<CollectCollection> collections;
  final List<PaymentIntentModel> paymentIntents;
  final List<Contribution> contributions;
  final List<NotificationEvent> notificationEvents;
  final NotificationPreferences notificationPreferences;
  final bool smsAccessEnabled;
  final bool smsAccessDenied;
  final bool isLoading;
  final String? lastError;

  CollectState copyWith({
    CollectProfile? currentProfile,
    List<CollectCollection>? collections,
    List<PaymentIntentModel>? paymentIntents,
    List<Contribution>? contributions,
    List<NotificationEvent>? notificationEvents,
    NotificationPreferences? notificationPreferences,
    bool? smsAccessEnabled,
    bool? smsAccessDenied,
    bool? isLoading,
    String? lastError,
  }) {
    return CollectState(
      currentProfile: currentProfile ?? this.currentProfile,
      collections: collections ?? this.collections,
      paymentIntents: paymentIntents ?? this.paymentIntents,
      contributions: contributions ?? this.contributions,
      notificationEvents: notificationEvents ?? this.notificationEvents,
      notificationPreferences:
          notificationPreferences ?? this.notificationPreferences,
      smsAccessEnabled: smsAccessEnabled ?? this.smsAccessEnabled,
      smsAccessDenied: smsAccessDenied ?? this.smsAccessDenied,
      isLoading: isLoading ?? this.isLoading,
      lastError: lastError,
    );
  }
}
