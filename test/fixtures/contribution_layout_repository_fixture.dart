import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';

import 'collect_repository_fixture.dart';

/// Synthetic layout-only payment fixture with no saved command or live backend.
/// Custody, session and provider handoff are covered by separate focused tests.
class ContributionLayoutRepository extends FixtureCollectRepository {
  ContributionLayoutRepository({
    super.seeded = true,
    super.fixtureNow,
    super.smsAccessChannel = const SmsAccessChannel(),
    super.profileOverride,
  });

  @override
  Future<ContributionCommandCheckpoint?> restoreContributionCommand(
    String collectionId,
  ) async => null;

  @override
  Future<PaymentIntentModel> prepareContributionIntent(
    PaymentIntentDraft draft,
  ) => createPaymentIntent(draft);
}
