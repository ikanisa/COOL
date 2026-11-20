part of 'collect_repository.dart';

abstract interface class MemberAccountState {
  CollectProfile? get currentProfile;
  bool get isLoading;
}

abstract interface class MemberAccountRepository {
  int get sessionGeneration;
  bool get isLive;
  Future<void> loadInitial();
  Future<CollectProfile> signInWithOtp({
    required String phone,
    required String otp,
    String? countryCode,
  });
  Future<CollectProfile> updateCurrentProfile({
    required String countryCode,
    String? momoProvider,
    String? momoNumber,
    String? momoPayCode,
  });
  Future<void> signOut();
}
