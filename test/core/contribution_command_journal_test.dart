import 'dart:convert';

import 'package:collect_app/core/payments/contribution_command.dart';
import 'package:collect_app/core/payments/contribution_command_journal.dart';
import 'package:collect_app/core/security/contribution_command_storage_contract.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/contribution_command_values.dart';

void main() {
  test(
    'original body canonical digest and owner partition exclude session',
    () {
      final body = commandBody();
      expect(body.toJson().keys.toSet(), {
        'collection',
        'p_expected_amount_rwf',
        'p_sender_phone_hash',
        'p_request_id',
      });
      expect(
        ContributionCommandBody.fromJson(jsonDecode(body.canonical)).canonical,
        body.canonical,
      );
      expect(body.sha256, hasLength(64));
      expect(
        commandWitness().owner.partitionId,
        commandWitness(
          session: '20000000-0000-0000-0000-000000000002',
        ).owner.partitionId,
      );
      expect(
        commandOwner(project: 'https://different.supabase.co').partitionId,
        isNot(commandOwner().partitionId),
      );
    },
  );
  for (final key in [
    'issuer',
    'owner_id',
    'auth_subject',
    'session_id',
    'retry_authorized',
    'launch_authorized',
    'extra',
  ]) {
    test('witness rejects invalid $key without JWT fallback', () {
      final row = commandWitnessWire();
      row[key] = switch (key) {
        'issuer' => 'https://different.supabase.co/auth/v1',
        'retry_authorized' || 'launch_authorized' => true,
        'session_id' => 'raw-bearer-is-not-session',
        'extra' => 1,
        _ => '10000000-0000-0000-0000-000000000099',
      };
      expect(
        () => ContributionSessionWitness.fromWire(
          row,
          expectedOwner: commandOwner(),
          now: DateTime.now(),
        ),
        throwsFormatException,
      );
    });
  }
  test(
    'two initial writers retain one original key and only one dispatch claim',
    () async {
      final storage = MemoryContributionStore();
      final a = ContributionCommandJournal(storage: storage),
          b = ContributionCommandJournal(storage: storage);
      final results = await Future.wait([
        a
            .prepare(commandWitness(), commandBody(), isCurrent: () => true)
            .then<Object>((v) => v, onError: (Object e) => e),
        b
            .prepare(
              commandWitness(),
              commandBody(request: '50000000-0000-0000-0000-000000000002'),
              isCurrent: () => true,
            )
            .then<Object>((v) => v, onError: (Object e) => e),
      ]);
      expect(results.whereType<ContributionCommandCheckpoint>(), hasLength(1));
      expect(results.whereType<ContributionRecoveryRequired>(), hasLength(1));
      final saved = (await a.read(commandOwner())).single;
      final claims = await Future.wait([
        a
            .claimDispatch(
              commandWitness(),
              saved.body.requestId,
              isCurrent: () => true,
            )
            .then<Object>((v) => v, onError: (Object e) => e),
        b
            .claimDispatch(
              commandWitness(),
              saved.body.requestId,
              isCurrent: () => true,
            )
            .then<Object>((v) => v, onError: (Object e) => e),
      ]);
      expect(claims.whereType<ContributionCommandCheckpoint>(), hasLength(1));
      expect(claims.whereType<ContributionRecoveryRequired>(), hasLength(1));
    },
  );
  for (final phase in ['prepare', 'dispatch', 'handoff']) {
    test(
      'lost $phase CAS ACK retains bytes and never grants the next effect',
      () async {
        final storage = MemoryContributionStore();
        final journal = ContributionCommandJournal(storage: storage);
        final witness = commandWitness();
        if (phase == 'prepare') {
          storage.loseNextAcknowledgement = true;
          await expectLater(
            journal.prepare(witness, commandBody(), isCurrent: () => true),
            throwsStateError,
          );
        } else {
          await journal.prepare(witness, commandBody(), isCurrent: () => true);
          if (phase == 'handoff') {
            await journal.claimDispatch(
              witness,
              commandRequestId,
              isCurrent: () => true,
            );
            await journal.retainReceipt(
              witness,
              commandRequestId,
              commandIntentId,
              isCurrent: () => true,
            );
          }
          storage.loseNextAcknowledgement = true;
          await expectLater(
            phase == 'dispatch'
                ? journal.claimDispatch(
                    witness,
                    commandRequestId,
                    isCurrent: () => true,
                  )
                : journal.claimProviderHandoff(
                    witness,
                    commandRequestId,
                    commandIntentId,
                    isCurrent: () => true,
                  ),
            throwsStateError,
          );
        }
        final restarted = ContributionCommandJournal(storage: storage);
        final saved = (await restarted.read(commandOwner())).single;
        expect(saved.body.canonical, commandBody().canonical);
        expect(saved.providerHandoffPossible, phase == 'handoff');
        await expectLater(
          restarted.prepare(
            witness,
            commandBody(request: '50000000-0000-0000-0000-000000000002'),
            isCurrent: () => true,
          ),
          throwsA(isA<ContributionRecoveryRequired>()),
        );
        if (phase != 'prepare') {
          await expectLater(
            restarted.claimDispatch(
              witness,
              commandRequestId,
              isCurrent: () => true,
            ),
            throwsA(isA<ContributionRecoveryRequired>()),
          );
        }
      },
    );
  }
  test(
    'A B A and project switch preserve distinct owner ciphertext partitions',
    () async {
      final storage = MemoryContributionStore(), aOwner = commandOwner();
      final a = ContributionCommandJournal(storage: storage);
      await a.prepare(commandWitness(), commandBody(), isCurrent: () => true);
      final bOwner = commandOwner(
        owner: '10000000-0000-0000-0000-000000000002',
      );
      await a.prepare(
        commandWitness(owner: bOwner),
        commandBody(),
        isCurrent: () => true,
      );
      final otherProject = commandOwner(project: 'https://other.supabase.co');
      await a.prepare(
        commandWitness(owner: otherProject),
        commandBody(),
        isCurrent: () => true,
      );
      expect(storage.rows, hasLength(3));
      final restored = (await ContributionCommandJournal(
        storage: storage,
      ).read(aOwner)).single;
      expect(restored.originalSessionId, commandSessionId);
      final renewed = commandWitness(
        session: '20000000-0000-0000-0000-000000000002',
      );
      await expectLater(
        a.claimDispatch(renewed, commandRequestId, isCurrent: () => true),
        throwsA(isA<ContributionRecoveryRequired>()),
      );
      expect((await a.read(aOwner)).single.originalSessionId, commandSessionId);
    },
  );
  test(
    'unknown lookup never clears uncertainty or promotes dispatch into launch',
    () async {
      final storage = MemoryContributionStore(), witness = commandWitness();
      final journal = ContributionCommandJournal(storage: storage);
      await journal.prepare(witness, commandBody(), isCurrent: () => true);
      var saved = await journal.claimDispatch(
        witness,
        commandRequestId,
        isCurrent: () => true,
      );
      final oldBody = saved.body.canonical;
      saved = await journal.retainObservation(
        witness,
        commandRequestId,
        ContributionCommandObservation.fromWire(
          commandObservationWire(saved),
          saved,
        ),
        isCurrent: () => true,
      );
      expect(saved.intentId, isNull);
      saved = await journal.retainObservation(
        witness,
        commandRequestId,
        ContributionCommandObservation.fromWire(
          commandObservationWire(
            saved,
            intentId: commandIntentId,
            status: 'cancelled',
          ),
          saved,
        ),
        isCurrent: () => true,
      );
      expect(saved.phase, ContributionCommandPhase.dispatchPossible);
      expect(saved.body.canonical, oldBody);
      await expectLater(
        journal.claimProviderHandoff(
          witness,
          commandRequestId,
          commandIntentId,
          isCurrent: () => true,
        ),
        throwsA(isA<ContributionRecoveryRequired>()),
      );
    },
  );
  test('handoff CAS is monotonic across restart and two writers', () async {
    final storage = MemoryContributionStore(), witness = commandWitness();
    final journal = ContributionCommandJournal(storage: storage);
    await journal.prepare(witness, commandBody(), isCurrent: () => true);
    await journal.claimDispatch(
      witness,
      commandRequestId,
      isCurrent: () => true,
    );
    await journal.retainReceipt(
      witness,
      commandRequestId,
      commandIntentId,
      isCurrent: () => true,
    );
    final claims = await Future.wait([
      journal
          .claimProviderHandoff(
            witness,
            commandRequestId,
            commandIntentId,
            isCurrent: () => true,
          )
          .then<Object>((v) => v, onError: (Object e) => e),
      ContributionCommandJournal(storage: storage)
          .claimProviderHandoff(
            witness,
            commandRequestId,
            commandIntentId,
            isCurrent: () => true,
          )
          .then<Object>((v) => v, onError: (Object e) => e),
    ]);
    expect(claims.whereType<ContributionCommandCheckpoint>(), hasLength(1));
    final restarted = ContributionCommandJournal(storage: storage);
    expect(
      (await restarted.read(commandOwner())).single.providerHandoffPossible,
      isTrue,
    );
    await expectLater(
      restarted.claimProviderHandoff(
        witness,
        commandRequestId,
        commandIntentId,
        isCurrent: () => true,
      ),
      throwsA(isA<ContributionRecoveryRequired>()),
    );
  });
  test(
    'unreadable unknown schema and failed custody never become absence',
    () async {
      final storage = MemoryContributionStore(), owner = commandOwner();
      storage.rows[owner.partitionId] = ContributionStoreSnapshot(
        partitionId: owner.partitionId,
        revision: 1,
        payload: contributionCanonicalJson({
          'schema_version': 2,
          'owner': owner.toJson(),
          'records': [],
        }),
      );
      final journal = ContributionCommandJournal(storage: storage);
      await expectLater(
        journal.prepare(commandWitness(), commandBody(), isCurrent: () => true),
        throwsFormatException,
      );
      expect(storage.commits, 0);
      storage.rows.clear();
      storage.failRead = true;
      await expectLater(
        journal.prepare(commandWitness(), commandBody(), isCurrent: () => true),
        throwsStateError,
      );
      storage.failRead = false;
      storage.failBeforeCommit = true;
      await expectLater(
        journal.prepare(commandWitness(), commandBody(), isCurrent: () => true),
        throwsStateError,
      );
      expect(storage.commits, 0);
    },
  );
  test('64 retained records refuse another command without eviction', () async {
    final owner = commandOwner(), storage = MemoryContributionStore();
    final records = List.generate(
      64,
      (i) => ContributionCommandCheckpoint.prepared(
        commandBody(
          request:
              '50000000-0000-0000-0000-${(i + 1).toString().padLeft(12, '0')}',
          group:
              '30000000-0000-0000-0000-${(i + 1).toString().padLeft(12, '0')}',
        ),
        commandWitness(),
      ).toJson(),
    );
    final payload = contributionCanonicalJson({
      'schema_version': 1,
      'owner': owner.toJson(),
      'records': records,
    });
    storage.rows[owner.partitionId] = ContributionStoreSnapshot(
      partitionId: owner.partitionId,
      revision: 1,
      payload: payload,
    );
    await expectLater(
      ContributionCommandJournal(storage: storage).prepare(
        commandWitness(),
        commandBody(
          request: '50000000-0000-0000-0000-000000000099',
          group: '30000000-0000-0000-0000-000000000099',
        ),
        isCurrent: () => true,
      ),
      throwsStateError,
    );
    expect(storage.rows[owner.partitionId]!.payload, payload);
    expect(storage.commits, 0);
  });
  test(
    'historical creation is rejected as current review and permit is one use',
    () {
      expect(
        () => ContributionIntentReview.fromWire(
          commandIntentWire(),
          collectionId: commandGroupId,
          intentId: commandIntentId,
          sessionId: commandSessionId,
        ),
        throwsFormatException,
      );
      final review = ContributionIntentReview.fromWire(
        commandReviewWire(),
        collectionId: commandGroupId,
        intentId: commandIntentId,
        sessionId: commandSessionId,
      );
      var current = true;
      final permit = ContributionLaunchPermit(
        review: review,
        isCurrent: () => current,
      );
      expect(permit.consume(), isTrue);
      expect(permit.consume(), isFalse);
      current = false;
      expect(
        ContributionLaunchPermit(
          review: review,
          isCurrent: () => current,
        ).consume(),
        isFalse,
      );
    },
  );
}
