import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/referral_attribution.dart';
import '../repositories/referral_repository.dart';
import 'supabase_client_provider.dart';

final referralRepositoryProvider = Provider<ReferralRepository>((ref) {
  return ReferralRepository(client: ref.read(supabaseClientProvider));
});

final activeReferralAttributionProvider =
    StateNotifierProvider<ReferralAttributionNotifier, ReferralAttribution?>(
      (ref) => ReferralAttributionNotifier(),
    );

class ReferralAttributionNotifier extends StateNotifier<ReferralAttribution?> {
  ReferralAttributionNotifier() : super(null);

  ReferralAttribution? captureUri(Uri uri, {required String route}) {
    final inviteId = uri.queryParameters['ri']?.trim();
    if (inviteId == null || inviteId.isEmpty) {
      return state;
    }

    final next = ReferralAttribution.fromUri(uri, route: route);
    state = next;
    return next;
  }

  void markOpened(String inviteId) {
    if (state?.inviteId != inviteId) {
      return;
    }

    state = state?.copyWith(openedLogged: true);
  }

  void clearIfMatches(String inviteId) {
    if (state?.inviteId == inviteId) {
      state = null;
    }
  }
}
