import 'package:collect_app/core/payments/contribution_command.dart';
import 'package:collect_app/core/security/contribution_command_storage_contract.dart';
import 'package:collect_app/core/security/hash_utils.dart';

const commandOwnerId = '10000000-0000-0000-0000-000000000001';
const commandAuthId = '11000000-0000-0000-0000-000000000001';
const commandSessionId = '20000000-0000-0000-0000-000000000001';
const commandGroupId = '30000000-0000-0000-0000-000000000001';
const commandIntentId = '40000000-0000-0000-0000-000000000001';
const commandRequestId = '50000000-0000-0000-0000-000000000001';
const commandProject = 'https://synthetic.supabase.co';
const commandHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
ContributionCommandOwner commandOwner({
  String project = commandProject,
  String owner = commandOwnerId,
  String auth = commandAuthId,
}) => ContributionCommandOwner(
  projectOrigin: project,
  principalId: owner,
  authSubject: auth,
);
Map<String, dynamic> commandWitnessWire({
  String session = commandSessionId,
  String owner = commandOwnerId,
  String auth = commandAuthId,
}) => {
  'contract_version': 1,
  'binding_kind': 'current_contribution_session',
  'issuer': '$commandProject/auth/v1',
  'owner_id': owner,
  'auth_subject': auth,
  'session_id': session,
  'expires_at': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 3600,
  'observed_at': DateTime.now().toUtc().toIso8601String(),
  'retry_authorized': false,
  'launch_authorized': false,
};
ContributionSessionWitness commandWitness({
  String session = commandSessionId,
  ContributionCommandOwner? owner,
}) => ContributionSessionWitness.fromWire(
  commandWitnessWire(
    session: session,
    owner: owner?.principalId ?? commandOwnerId,
    auth: owner?.authSubject ?? commandAuthId,
  )..['issuer'] = '${owner?.projectOrigin ?? commandProject}/auth/v1',
  expectedOwner: owner ?? commandOwner(),
  now: DateTime.now(),
);
ContributionCommandBody commandBody({
  String request = commandRequestId,
  String group = commandGroupId,
  int amount = 5000,
}) => ContributionCommandBody(
  collectionId: group,
  amountRwf: amount,
  senderPhoneHash: commandHash,
  requestId: request,
);
Map<String, dynamic> commandIntentWire({
  String id = commandIntentId,
  String session = commandSessionId,
  String status = 'pending',
  String receiver = '0788123456',
  String? senderHash,
}) => {
  'id': id,
  'collection_id': commandGroupId,
  'amount_minor': 5000,
  'currency': 'RWF',
  'rail': 'rwanda_momo',
  'status': status,
  'receiver_momo_number': receiver,
  'network': 'mtn_momo',
  'receiver_label': 'Synthetic receiver',
  'receiver_momo_number_hash': '',
  'sender_phone_hash': senderHash ?? HashUtils.phoneHash('0788123456'),
  'originating_session_id': session,
  'created_at': '2026-10-20T00:00:00.000Z',
  'expires_at': '2030-10-20T00:00:00.000Z',
};
Map<String, dynamic> commandReviewWire({
  String session = commandSessionId,
  String status = 'pending',
  String receiver = '0788123456',
  String? senderHash,
}) => {
  'contract_version': 1,
  'review_status': 'current',
  'collection_id': commandGroupId,
  'intent_id': commandIntentId,
  'reviewed_session_id': session,
  'collection_revision': 2,
  'observed_at': DateTime.now().toUtc().toIso8601String(),
  'external_payment': 'unknown',
  'retry_authorized': false,
  'launch_authorized': true,
  'intent': commandIntentWire(
    session: session,
    status: status,
    receiver: receiver,
    senderHash: senderHash,
  ),
};
Map<String, dynamic> commandObservationWire(
  ContributionCommandCheckpoint record, {
  String? intentId,
  String status = 'pending',
}) => {
  'contract_version': 1,
  'request_id': record.body.requestId,
  'original_session_id': record.originalSessionId,
  'collection_id': record.body.collectionId,
  'body_sha256': record.body.sha256,
  'command_status': intentId == null ? 'unknown' : 'receipt_retained',
  'observed_at': DateTime.now().toUtc().toIso8601String(),
  'external_payment': 'unknown',
  'retry_authorized': false,
  'launch_authorized': false,
  'observed_intent': intentId == null
      ? null
      : {'id': intentId, 'status': status},
};

/// Atomic only inside this test process. Native/browser cross-writer guarantees
/// require the separate actual platform tests; this fake grants no such proof.
class MemoryContributionStore implements ContributionCommandProtectedStorage {
  final rows = <String, ContributionStoreSnapshot>{};
  int commits = 0;
  bool failRead = false,
      failBeforeCommit = false,
      loseNextAcknowledgement = false;
  @override
  Future<ContributionStoreSnapshot> read(String partitionId) async {
    if (failRead) throw StateError('Synthetic protected read failure');
    return rows[partitionId] ??
        ContributionStoreSnapshot(
          partitionId: partitionId,
          revision: 0,
          payload: null,
        );
  }

  @override
  Future<ContributionStoreCasResult> compareAndSet(
    String partitionId,
    int expectedRevision,
    String payload,
  ) async {
    if (failBeforeCommit) {
      throw StateError('Synthetic storage/key/full failure');
    }
    final before =
        rows[partitionId] ??
        ContributionStoreSnapshot(
          partitionId: partitionId,
          revision: 0,
          payload: null,
        );
    if (before.revision != expectedRevision) {
      return ContributionStoreCasResult(committed: false, snapshot: before);
    }
    final next = ContributionStoreSnapshot(
      partitionId: partitionId,
      revision: expectedRevision + 1,
      payload: payload,
    );
    rows[partitionId] = next;
    commits++;
    if (loseNextAcknowledgement) {
      loseNextAcknowledgement = false;
      throw StateError('Synthetic lost commit acknowledgement');
    }
    return ContributionStoreCasResult(committed: true, snapshot: next);
  }
}
