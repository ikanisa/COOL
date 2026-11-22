import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';

import '../../core/payments/contribution_command.dart';
import '../../core/payments/contribution_command_journal.dart';
import '../../core/payments/momo_ussd_intent_guard.dart';
import '../../core/security/phone_normalizer.dart';
import '../../core/data/exact_json_values.dart';
import '../../core/security/hash_utils.dart';
import '../../core/security/play_integrity_service.dart';
import '../../core/security/public_id_generator.dart';
import '../../core/security/sms_access_channel.dart';
import '../../core/security/durable_sms_receipt.dart';
import '../../core/cloudflare/realtime_invalidation.dart';
import '../../core/cloudflare/cloudflare_module.dart';
import '../../features/privacy/privacy_providers.dart';
import '../models/collect_models.dart';
import '../models/member_history_page.dart';
import '../models/receipt_sms_consent.dart';
import 'receipt_sms_pending_store.dart';
import 'collect_offline_cache.dart';
import 'member_account_repository.dart';
import 'member_group_repository.dart';
import 'runtime_control_contract.dart';
import 'payment_help_pending_store.dart';

export '../models/member_history_page.dart';
export '../../core/payments/contribution_command.dart';
export 'member_account_repository.dart';
export 'member_group_repository.dart';

part 'collect_repository_providers.dart';
part 'collect_repository_state.dart';
part 'collect_repository_live_reader.dart';
part 'collect_repository_helpers.dart';
part 'collect_repository_history.dart';
part 'collect_repository_member_history.dart';
part 'member_financial_repositories.dart';
part 'member_receipt_sms_repository.dart';
part 'collect_repository_contribution_actions.dart';
part 'collect_repository_payment_help.dart';
part 'collect_repository_sms_intake.dart';
part 'collect_repository_contribution_commands.dart';
part 'collect_invitation_protection.dart';
part 'collect_repository_notification_actions.dart';
part 'collect_repository_receipt_sms_actions.dart';
part 'collect_repository_group_actions.dart';
part 'collect_repository_group_metadata.dart';
part 'collect_repository_record_reads.dart';
part 'collect_repository_offline_snapshot.dart';
part 'collect_repository_discovery.dart';
part 'collect_repository_snapshot_sync.dart';
part 'collect_repository_session.dart';
part 'collect_repository_profile.dart';

class CollectRepository extends StateNotifier<CollectState>
    with
        _CollectContributionActions,
        _CollectPaymentHelp,
        _CollectMemberSmsIntake,
        _CollectContributionCommands,
        _CollectNotificationActions,
        _CollectReceiptSmsActions,
        _CollectGroupMetadata,
        _CollectGroupActions,
        _CollectGroupInvitations,
        _CollectRecordReads,
        _CollectMemberHistory,
        _CollectRepositoryOfflineSnapshot,
        _CollectRepositoryDiscovery,
        _CollectRepositorySnapshotSync,
        _CollectRepositorySession,
        _CollectRepositoryProfile
    implements
        MemberAccountRepository,
        MemberGroupRepository,
        MemberGroupManagementRepository,
        MemberGroupInvitationRepository,
        MemberPaymentRepository,
        MemberReceiptSmsRepository {
  CollectRepository({
    CollectCloudflareClient? backend,
    ReceiptSmsPendingStore? receiptSmsPendingStore,
    PaymentHelpPendingStore? paymentHelpPendingStore,
    ContributionCommandJournal? contributionCommandJournal,
    SmsAccessChannel smsAccessChannel = const SmsAccessChannel(),
    CollectOfflineCache? offlineCache,
    void Function()? onSignOutStarted,
  }) : this._(
         backend,
         smsAccessChannel,
         _emptyCollectState(),
         false,
         offlineCache ?? const CollectOfflineCache.protected(),
         onSignOutStarted,
         receiptSmsPendingStore ?? const NativeReceiptSmsPendingStore(),
         paymentHelpPendingStore ?? PaymentHelpPendingStore(),
         contributionCommandJournal ?? ContributionCommandJournal(),
       );

  /// Test harness injection only. App entrypoints use the empty live constructor.
  /// Synthetic records belong outside lib and must be supplied explicitly.
  CollectRepository.fixture({
    required CollectState initialState,
    CollectCloudflareClient? backend,
    ReceiptSmsPendingStore? receiptSmsPendingStore,
    PaymentHelpPendingStore? paymentHelpPendingStore,
    ContributionCommandJournal? contributionCommandJournal,
    SmsAccessChannel smsAccessChannel = const SmsAccessChannel(),
    Map<String, List<CollectMember>> fixtureAdditionalMembers = const {},
    CollectOfflineCache? offlineCache,
    void Function()? onSignOutStarted,
  }) : this._(
         backend,
         smsAccessChannel,
         initialState,
         true,
         offlineCache ?? const CollectOfflineCache(),
         onSignOutStarted,
         receiptSmsPendingStore ?? const NativeReceiptSmsPendingStore(),
         paymentHelpPendingStore ?? PaymentHelpPendingStore(),
         contributionCommandJournal ?? ContributionCommandJournal(),
         fixtureAdditionalMembers,
       );

  CollectRepository._(
    this._backend,
    this._smsAccessChannel,
    CollectState initialState,
    this._allowLocalWrites,
    this._offlineCache,
    this._onSignOutStarted,
    this._receiptSmsPendingStore,
    this._paymentHelpPendingStore,
    this._contributionCommandJournal, [
    Map<String, List<CollectMember>> fixtureAdditionalMembers = const {},
  ]) : _fixtureAdditionalMembers = Map.unmodifiable({
         for (final entry in fixtureAdditionalMembers.entries)
           entry.key: List<CollectMember>.unmodifiable(entry.value),
       }),
       super(initialState) {
    _observeAuthSession();
  }

  @override
  final CollectCloudflareClient? _backend;
  @override
  final ReceiptSmsPendingStore _receiptSmsPendingStore;
  @override
  late final _CollectLiveReader _liveReader = _CollectLiveReader(_backend);
  @override
  final SmsAccessChannel _smsAccessChannel;
  @override
  final bool _allowLocalWrites;
  @override
  final CollectOfflineCache _offlineCache;
  @override
  final PaymentHelpPendingStore _paymentHelpPendingStore;
  @override
  final ContributionCommandJournal _contributionCommandJournal;
  @override
  final void Function()? _onSignOutStarted;
  @override
  final Map<String, List<CollectMember>> _fixtureAdditionalMembers;
  static const _sharedUuid = Uuid();
  @override
  Uuid get _uuid => _sharedUuid;

  @override
  void dispose() {
    _stopObservingAuthSession();
    _stopRealtimeSync();
    _historyInvalidationListeners.clear();
    super.dispose();
  }

  @override
  CollectProfile _requireProfile() {
    final profile = state.currentProfile;
    if (profile == null) throw StateError('Sign in first');
    return profile;
  }

  @override
  CollectProfile _requireReadyProfile() {
    final profile = _requireProfile();
    if (!profile.isComplete) {
      throw const FormatException('Complete your Rwanda MoMo profile first.');
    }
    return profile;
  }

  @override
  CollectCollection _requireActiveCollection(String collectionId) {
    final collection = collectionById(collectionId);
    if (collection.isArchived) {
      throw StateError(
        'This group is archived. New contributions and group changes are off.',
      );
    }
    return collection;
  }

  @override
  CollectProfile _requireCollectionOwner(
    CollectCollection collection, {
    required String action,
  }) {
    final profile = _requireProfile();
    if (collection.creatorUserId != profile.id) {
      throw StateError('Only the group owner can $action.');
    }
    return profile;
  }
}
