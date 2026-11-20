part of 'collect_repository.dart';

abstract interface class MemberReceiptSmsRepository {
  int get sessionGeneration;
  Future<void> loadInitial();

  ReceiptSmsConsentView receiptSmsConsentFor(String group);
  PendingReceiptSmsRequest? receiptSmsCurrentPending(String group);
  Future<void> refreshReceiptSmsConsent(String group);
  Future<void> setReceiptSmsConsent(String group, {required bool optIn});
  Future<void> retryReceiptSmsConsent(String group);
  Future<void> withdrawReceiptSmsAndRecover(String group);
  Future<void> supersedeReceiptSmsRequests(String group);
}
