import 'dart:async';
import 'dart:convert';
import 'package:collect_app/shared/models/receipt_sms_consent.dart';
import 'package:collect_app/shared/repositories/receipt_sms_pending_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../support/receipt_sms_harness.dart';

Future<void> _ticks() async {
  for (var i = 0; i < 16; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _until(bool Function() ready) async {
  for (var i = 0; i < 200; i++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  throw StateError('Synthetic asynchronous boundary was not reached.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<ReceiptSmsHarness> harness() async {
    final h = await ReceiptSmsHarness.create();
    addTearDown(h.close);
    return h;
  }

  test(
    'no defaults or cached notification choice can authorize receipt SMS',
    () async {
      final h = await harness();
      expect(h.repo.receiptSmsConsentFor(smsGroup).consent, isNull);
      await expectLater(
        h.repo.setReceiptSmsConsent(smsGroup, optIn: true),
        throwsStateError,
      );
      expect(h.writes, isEmpty);
      expect(h.reads, isEmpty);
      expect(h.store.path(smsUser).existsSync(), isFalse);
    },
  );
  test('unsupported service stays unavailable and cannot save', () async {
    final h = await harness();
    h.unsupported = true;
    await expectLater(
      h.repo.refreshReceiptSmsConsent(smsGroup),
      throwsA(isA<Exception>()),
    );
    expect(h.repo.receiptSmsConsentFor(smsGroup).supportUnavailable, isTrue);
    await expectLater(
      h.repo.setReceiptSmsConsent(smsGroup, optIn: true),
      throwsStateError,
    );
    expect(h.writes, isEmpty);
  });
  test(
    'durable claim completes before HTTP; ACK is recorded-only until a separate current read',
    () async {
      final h = await harness();
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      h.store.claimGate = Completer<void>();
      final saving = h.repo.setReceiptSmsConsent(smsGroup, optIn: true);
      await _ticks();
      expect(h.writes, isEmpty);
      h.store.claimGate!.complete();
      await saving;
      expect(h.writes, hasLength(1));
      expect(h.reads, hasLength(1));
      final view = h.repo.receiptSmsConsentFor(smsGroup);
      expect(view.recordedRevision, 1);
      expect(view.needsRefresh, isTrue);
      expect(view.consent!.optIn, isFalse);
      expect(view.pending, isNull);
      expect(
        (await h.store.read(userId: smsUser, collectionId: smsGroup)).pending,
        isEmpty,
      );
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      expect(h.repo.receiptSmsConsentFor(smsGroup).consent!.effective, isTrue);
    },
  );
  test(
    'repository reconstruction retains a committed unknown write; matching GET never resolves it',
    () async {
      final h = await harness();
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      h.loseReply = true;
      await expectLater(
        h.repo.setReceiptSmsConsent(smsGroup, optIn: true),
        throwsA(isA<TimeoutException>()),
      );
      final original = (await h.store.read(
        userId: smsUser,
        collectionId: smsGroup,
      )).pending.single;
      expect(original, isNotNull);
      final disk = await h.store.path(smsUser).readAsString();
      expect(disk, contains(original.requestId));
      for (final forbidden in [
        'access_token',
        'refresh_token',
        'phone',
        'p_collection_id',
        'p_opt_in',
      ]) {
        expect(disk, isNot(contains(forbidden)));
      }
      h.reconstruct();
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      final view = h.repo.receiptSmsConsentFor(smsGroup);
      expect(view.consent!.optIn, isTrue);
      expect(view.pending!.requestId, original.requestId);
      await expectLater(
        h.repo.setReceiptSmsConsent(smsGroup, optIn: false),
        throwsStateError,
      );
      expect(h.writes, hasLength(1));
      await h.repo.retryReceiptSmsConsent(smsGroup);
      expect(h.writes, hasLength(2));
      expect(h.writes[1], h.writes[0]);
      expect(
        (await h.store.read(userId: smsUser, collectionId: smsGroup)).pending,
        isEmpty,
      );
      expect(h.repo.receiptSmsConsentFor(smsGroup).needsRefresh, isTrue);
    },
  );
  test(
    'delayed first opt-in cannot be overtaken by a new no-op withdrawal after reconstruction',
    () async {
      final h = await harness();
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      h.writeGate = Completer<void>();
      final first = h.repo.setReceiptSmsConsent(smsGroup, optIn: true);
      await _until(() => h.writes.length == 1);
      expect(h.writes, hasLength(1));
      final original = h.writes.single['p_request_id'];
      h.reconstruct();
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      expect(h.repo.receiptSmsConsentFor(smsGroup).consent!.optIn, isFalse);
      await expectLater(
        h.repo.setReceiptSmsConsent(smsGroup, optIn: false),
        throwsStateError,
      );
      expect(h.writes, hasLength(1));
      final firstResult = expectLater(first, throwsStateError);
      h.writeGate!.complete();
      await firstResult;
      await h.repo.retryReceiptSmsConsent(smsGroup);
      expect(h.writes, hasLength(2));
      expect(h.writes.last['p_request_id'], original);
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      expect(h.repo.receiptSmsConsentFor(smsGroup).consent!.optIn, isTrue);
    },
  );
  test(
    'two repository instances cannot claim conflicting choices for one owner/group',
    () async {
      final h = await harness(),
          other = ReceiptSmsRepository(
            h.client,
            FileReceiptSmsPendingStore(h.directory),
          );
      addTearDown(other.dispose);
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      await other.refreshReceiptSmsConsent(smsGroup);
      h.writeGate = Completer<void>();
      final first = h.repo.setReceiptSmsConsent(smsGroup, optIn: true),
          second = expectLater(
            other.setReceiptSmsConsent(smsGroup, optIn: false),
            throwsStateError,
          );
      await _until(() => h.writes.length == 1);
      await second;
      expect(h.writes, hasLength(1));
      expect(other.receiptSmsConsentFor(smsGroup).pending!.optIn, isTrue);
      h.writeGate!.complete();
      await first;
      final original = h.writes.single['p_request_id'];
      await other.refreshReceiptSmsConsent(smsGroup);
      final retained = other.receiptSmsConsentFor(smsGroup);
      expect(retained.storageAvailable, isTrue);
      expect(retained.pending!.requestId, original);
      expect(retained.recordedRevision, isNull);
      await expectLater(
        other.setReceiptSmsConsent(smsGroup, optIn: false),
        throwsStateError,
      );
      expect(h.writes, hasLength(1));
      await other.retryReceiptSmsConsent(smsGroup);
      expect(h.writes, hasLength(2));
      expect(h.writes.last['p_request_id'], original);
      expect(h.current(smsGroup)['decision_revision'], 1);
    },
  );
  test(
    'another instance ACK removal can be explicitly archived, preserving the unknown original identity',
    () async {
      final h = await harness();
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      h.loseReply = true;
      await expectLater(
        h.repo.setReceiptSmsConsent(smsGroup, optIn: true),
        throwsA(isA<TimeoutException>()),
      );
      final original = h.repo.receiptSmsConsentFor(smsGroup).pending!;
      final other = ReceiptSmsRepository(
        h.client,
        FileReceiptSmsPendingStore(h.directory),
      );
      addTearDown(other.dispose);
      await other.refreshReceiptSmsConsent(smsGroup);
      await other.retryReceiptSmsConsent(smsGroup);
      expect(
        (await h.store.read(userId: smsUser, collectionId: smsGroup)).pending,
        isEmpty,
      );
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      expect(
        h.repo.receiptSmsConsentFor(smsGroup).pending!.sameRequest(original),
        isTrue,
      );
      expect(
        h.repo.receiptSmsConsentFor(smsGroup).recordedDecisionRevision,
        isNull,
      );
      await h.repo.supersedeReceiptSmsRequests(smsGroup);
      final archived = await h.store.read(
        userId: smsUser,
        collectionId: smsGroup,
      );
      expect(archived.pending, isEmpty);
      expect(archived.superseded.single.request.toJson(), original.toJson());
      expect(archived.superseded.single.observedDecisionRevision, 1);
      expect(h.repo.receiptSmsConsentFor(smsGroup).recordedRevision, isNull);
      expect(h.writes, hasLength(2));
    },
  );
  test(
    'healthy reread and higher-head CAS preserve a newer same-session native request',
    () async {
      final h = await harness();
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      h.loseReply = true;
      await expectLater(
        h.repo.setReceiptSmsConsent(smsGroup, optIn: true),
        throwsA(isA<TimeoutException>()),
      );
      final original = h.repo.receiptSmsConsentFor(smsGroup).pending!;
      final other = ReceiptSmsRepository(
        h.client,
        FileReceiptSmsPendingStore(h.directory),
      );
      addTearDown(other.dispose);
      await other.refreshReceiptSmsConsent(smsGroup);
      await other.retryReceiptSmsConsent(smsGroup);
      await other.refreshReceiptSmsConsent(smsGroup);
      h.writeGate = Completer<void>();
      final changing = other.setReceiptSmsConsent(smsGroup, optIn: false);
      await _until(() => h.writes.length == 3);
      final newer = (await h.store.read(
        userId: smsUser,
        collectionId: smsGroup,
      )).pending.single;
      final before = await h.store.path(smsUser).readAsString();
      await expectLater(
        h.store.supersede(
          userId: smsUser,
          collectionId: smsGroup,
          knownRequests: [original],
          observedDecisionRevision: 1,
        ),
        throwsStateError,
      );
      expect(await h.store.path(smsUser).readAsString(), before);
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      expect(
        h.repo.receiptSmsConsentFor(smsGroup).recovery.pending,
        hasLength(2),
      );
      await h.repo.supersedeReceiptSmsRequests(smsGroup);
      final retained = await h.store.read(
        userId: smsUser,
        collectionId: smsGroup,
      );
      expect(retained.pending.single.toJson(), newer.toJson());
      expect(retained.superseded.single.request.toJson(), original.toJson());
      expect(h.writes, hasLength(3));
      h.writeGate!.complete();
      await changing;
      expect(h.current(smsGroup)['decision_revision'], 2);
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      expect(h.repo.receiptSmsConsentFor(smsGroup).consent!.optIn, isFalse);
    },
  );
  test(
    'retained superseded history and last observed status reject a lower decision head',
    () async {
      final h = await harness();
      await h.store
          .path(smsUser)
          .writeAsString(
            jsonEncode(
              ReceiptSmsRecoveryState(
                superseded: [ReceiptSmsSuperseded(pending(1), 5)],
              ).toJson(),
            ),
            flush: true,
          );
      await expectLater(
        h.repo.refreshReceiptSmsConsent(smsGroup),
        throwsFormatException,
      );
      h.remote['$smsUser/$smsGroup'] = smsRead(smsGroup, decisionRevision: 5);
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      h.alterRead = (row) => {...row, 'decision_revision': 4};
      await expectLater(
        h.repo.refreshReceiptSmsConsent(smsGroup),
        throwsFormatException,
      );
      expect(
        h.repo.receiptSmsConsentFor(smsGroup).consent!.decisionRevision,
        5,
      );
      expect(h.writes, isEmpty);
    },
  );
  test(
    'healthy custody cannot reuse a known request UUID with changed metadata',
    () async {
      final h = await harness();
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      h.loseReply = true;
      await expectLater(
        h.repo.setReceiptSmsConsent(smsGroup, optIn: true),
        throwsA(isA<TimeoutException>()),
      );
      final original = h.repo.receiptSmsConsentFor(smsGroup).pending!;
      final changed = PendingReceiptSmsRequest.decode({
        ...original.toJson(),
        'opt_in': false,
      });
      await h.store
          .path(smsUser)
          .writeAsString(
            jsonEncode(ReceiptSmsRecoveryState(pending: [changed]).toJson()),
            flush: true,
          );
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      final view = h.repo.receiptSmsConsentFor(smsGroup);
      expect(view.storageAvailable, isFalse);
      expect(view.pending!.toJson(), original.toJson());
      await expectLater(
        h.repo.setReceiptSmsConsent(smsGroup, optIn: false),
        throwsStateError,
      );
      expect(h.writes, hasLength(1));
    },
  );
  test(
    'new session of the same user retains old-session metadata and blocks conflicting changes/retry',
    () async {
      final h = await harness();
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      h.loseReply = true;
      await expectLater(
        h.repo.setReceiptSmsConsent(smsGroup, optIn: true),
        throwsA(isA<TimeoutException>()),
      );
      final original = await h.store.path(smsUser).readAsString();
      await h.login(smsUser, smsNextSession);
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      expect(
        h.repo.receiptSmsPendingBelongsToCurrentSession(smsGroup),
        isFalse,
      );
      await expectLater(
        h.repo.setReceiptSmsConsent(smsGroup, optIn: false),
        throwsStateError,
      );
      await expectLater(
        h.repo.retryReceiptSmsConsent(smsGroup),
        throwsStateError,
      );
      expect(h.writes, hasLength(1));
      expect(await h.store.path(smsUser).readAsString(), original);
    },
  );
  test(
    'other account cannot view or overwrite the first account recovery metadata',
    () async {
      final h = await harness();
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      h.loseReply = true;
      await expectLater(
        h.repo.setReceiptSmsConsent(smsGroup, optIn: true),
        throwsA(isA<TimeoutException>()),
      );
      final original = await h.store.path(smsUser).readAsString();
      await h.login(smsOther, smsNextSession);
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      expect(h.repo.receiptSmsConsentFor(smsGroup).pending, isNull);
      expect(h.repo.receiptSmsConsentFor(smsGroup).consent!.optIn, isFalse);
      expect(await h.store.path(smsUser).readAsString(), original);
    },
  );
  test(
    'a different group read cannot replace the selected group state',
    () async {
      final h = await harness();
      h.readGates[smsGroup] = Completer<http.Response>();
      final first = h.repo.refreshReceiptSmsConsent(smsGroup);
      await _ticks();
      h.remote['$smsUser/$smsGroupB'] = smsRead(
        smsGroupB,
        optIn: true,
        revision: 1,
      );
      await h.repo.refreshReceiptSmsConsent(smsGroupB);
      h.readGates[smsGroup]!.complete(
        http.Response(jsonEncode(smsRead(smsGroup)), 200),
      );
      await first;
      expect(h.repo.receiptSmsConsentFor(smsGroupB).consent!.optIn, isTrue);
      expect(h.repo.receiptSmsConsentFor(smsGroup).consent!.optIn, isFalse);
    },
  );
  test(
    'late status from a previous same-user auth session is rejected',
    () async {
      final h = await harness();
      h.readGates[smsGroup] = Completer<http.Response>();
      final first = h.repo.refreshReceiptSmsConsent(smsGroup);
      await _until(() => h.reads.contains(smsGroup));
      await h.login(smsUser, smsNextSession);
      final failed = expectLater(first, throwsStateError);
      h.readGates[smsGroup]!.complete(
        http.Response(
          jsonEncode(smsRead(smsGroup, optIn: true, revision: 1)),
          200,
        ),
      );
      await failed;
      expect(h.repo.receiptSmsConsentFor(smsGroup).consent, isNull);
      expect(h.writes, isEmpty);
    },
  );
  test(
    'corrupt durable custody is preserved and disables changes without inventing an empty journal',
    () async {
      final h = await harness();
      const bytes = '{"malformed":true}';
      await h.store.path(smsUser).writeAsString(bytes, flush: true);
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      expect(h.repo.receiptSmsConsentFor(smsGroup).storageAvailable, isFalse);
      await expectLater(
        h.repo.setReceiptSmsConsent(smsGroup, optIn: true),
        throwsStateError,
      );
      expect(h.writes, isEmpty);
      expect(await h.store.path(smsUser).readAsString(), bytes);
    },
  );
  test(
    'failed pre-dispatch persistence cannot send HTTP and can recover without inventing a server result',
    () async {
      final h = await harness();
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      h.store.failClaims = true;
      await expectLater(
        h.repo.setReceiptSmsConsent(smsGroup, optIn: true),
        throwsA(isA<Exception>()),
      );
      expect(h.writes, isEmpty);
      expect(
        h.repo.receiptSmsConsentFor(smsGroup).unpersistedRequestIds,
        isNotEmpty,
      );
      h.store.failClaims = false;
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      expect(h.repo.receiptSmsConsentFor(smsGroup).pending, isNull);
    },
  );
  test(
    'foreign and cached-only groups do not authorize receipt consent mutations',
    () async {
      final h = await harness();
      await expectLater(
        h.repo.refreshReceiptSmsConsent(smsForeign),
        throwsStateError,
      );
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      h.repo.offline();
      await expectLater(
        h.repo.setReceiptSmsConsent(smsGroup, optIn: true),
        throwsStateError,
      );
      expect(h.writes, isEmpty);
    },
  );
  test(
    'blocked phone opt-in stays On but ineffective; withdrawal does not require a new phone proof',
    () async {
      final h = await harness();
      h.remote['$smsUser/$smsGroup'] = smsRead(
        smsGroup,
        optIn: true,
        revision: 1,
        status: 'blocked_phone_binding',
        binding: false,
        proof: false,
        available: false,
        reason: 'current_phone_verification_required',
      );
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      final status = h.repo.receiptSmsConsentFor(smsGroup).consent!;
      expect(status.optIn, isTrue);
      expect(status.effective, isFalse);
      await expectLater(
        h.repo.setReceiptSmsConsent(smsGroup, optIn: true),
        throwsStateError,
      );
      await h.repo.setReceiptSmsConsent(smsGroup, optIn: false);
      expect(h.writes.single['p_opt_in'], isFalse);
    },
  );
  for (final entry in <String, Object?>{
    'wrong group': smsGroupB,
    'wrong version': '1',
    'invented delivery': true,
    'unknown status': 'sent',
    'bool revision': true,
    'string decision': '0',
    'float decision': 0.0,
    'unsafe decision': 9007199254740992,
  }.entries) {
    test('current status rejects ${entry.key}', () async {
      final h = await harness();
      h.alterRead = (row) => {
        ...row,
        switch (entry.key) {
          'wrong group' => 'collection_id',
          'wrong version' => 'contract_version',
          'invented delivery' => 'delivery_confirmed',
          'unknown status' => 'authorization_status',
          'bool revision' => 'revision',
          _ => 'decision_revision',
        }: entry.value,
      };
      await expectLater(
        h.repo.refreshReceiptSmsConsent(smsGroup),
        throwsFormatException,
      );
      expect(h.repo.receiptSmsConsentFor(smsGroup).consent, isNull);
      expect(h.writes, isEmpty);
    });
  }
  for (final field in [
    'recipient_user_id',
    'originating_session_id',
    'request_id',
    'collection_id',
    'recorded_state_only',
    'opt_in',
    'consent_revision',
    'decision_revision',
  ]) {
    test(
      'malformed ACK $field retains original durable request until exact valid replay',
      () async {
        final h = await harness();
        await h.repo.refreshReceiptSmsConsent(smsGroup);
        h.alterAck = (row) => {
          ...row,
          field: field == 'recorded_state_only'
              ? false
              : field == 'opt_in'
              ? false
              : field == 'consent_revision' || field == 'decision_revision'
              ? 99
              : smsOther,
        };
        await expectLater(
          h.repo.setReceiptSmsConsent(smsGroup, optIn: true),
          throwsFormatException,
        );
        final original = (await h.store.read(
          userId: smsUser,
          collectionId: smsGroup,
        )).pending.single;
        expect(original, isNotNull);
        await h.repo.refreshReceiptSmsConsent(smsGroup);
        expect(
          h.repo.receiptSmsConsentFor(smsGroup).pending!.requestId,
          original.requestId,
        );
        h.alterAck = null;
        await h.repo.retryReceiptSmsConsent(smsGroup);
        expect(h.writes.last['p_request_id'], original.requestId);
      },
    );
  }
  test(
    'fresh-session explicit withdrawal durably coexists with delayed opt-in and fences its later commit',
    () async {
      final h = await harness();
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      final oldGate = Completer<void>();
      h.sessionWriteGates[smsSession] = oldGate;
      final first = h.repo.setReceiptSmsConsent(smsGroup, optIn: true);
      final firstResult = expectLater(first, throwsStateError);
      await _until(() => h.writes.length == 1);
      final original = (await h.store.read(
        userId: smsUser,
        collectionId: smsGroup,
      )).pending.single;
      await h.login(smsUser, smsNextSession);
      h.reconstruct();
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      final fenceGate = Completer<void>();
      h.sessionWriteGates[smsNextSession] = fenceGate;
      final fence = h.repo.withdrawReceiptSmsAndRecover(smsGroup);
      await _until(() => h.writes.length == 2);
      final beforeHttp = (await h.store.read(
        userId: smsUser,
        collectionId: smsGroup,
      )).pending;
      expect(beforeHttp, hasLength(2));
      expect(
        beforeHttp
            .singleWhere((r) => r.requestId == original.requestId)
            .toJson(),
        original.toJson(),
      );
      final fresh = beforeHttp.singleWhere(
        (r) => r.sessionId == smsNextSession,
      );
      expect(fresh.optIn, isFalse);
      expect(fresh.expectedRevision, 0);
      expect(fresh.expectedDecisionRevision, 0);
      fenceGate.complete();
      await fence;
      expect(h.current(smsGroup)['revision'], 0);
      expect(h.current(smsGroup)['decision_revision'], 1);
      expect(h.current(smsGroup)['opt_in'], isFalse);
      final custody = await h.store.read(
        userId: smsUser,
        collectionId: smsGroup,
      );
      expect(custody.pending, isEmpty);
      expect(custody.superseded.single.request.toJson(), original.toJson());
      oldGate.complete();
      await firstResult;
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      expect(h.repo.receiptSmsConsentFor(smsGroup).consent!.optIn, isFalse);
      expect(h.writes, hasLength(2));
      expect(
        h.repo
            .receiptSmsConsentFor(smsGroup)
            .recovery
            .superseded
            .single
            .observedDecisionRevision,
        1,
      );
    },
  );
  test(
    'opposite ordering retains conflicted fence; explicit higher-head disposition never invents the original outcome',
    () async {
      final h = await harness();
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      final oldGate = Completer<void>();
      h.sessionWriteGates[smsSession] = oldGate;
      final first = h.repo.setReceiptSmsConsent(smsGroup, optIn: true);
      final firstResult = expectLater(first, throwsStateError);
      await _until(() => h.writes.length == 1);
      await h.login(smsUser, smsNextSession);
      h.reconstruct();
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      final newGate = Completer<void>();
      h.sessionWriteGates[smsNextSession] = newGate;
      final fence = h.repo.withdrawReceiptSmsAndRecover(smsGroup);
      final fenceResult = expectLater(fence, throwsA(isA<Exception>()));
      await _until(() => h.writes.length == 2);
      oldGate.complete();
      await firstResult;
      newGate.complete();
      await fenceResult;
      expect(
        (await h.store.read(userId: smsUser, collectionId: smsGroup)).pending,
        hasLength(2),
      );
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      expect(h.repo.receiptSmsConsentFor(smsGroup).consent!.optIn, isTrue);
      await h.repo.supersedeReceiptSmsRequests(smsGroup);
      expect(h.writes, hasLength(2));
      final kept = await h.store.read(userId: smsUser, collectionId: smsGroup);
      expect(kept.pending, isEmpty);
      expect(kept.superseded, hasLength(2));
      expect(kept.superseded.map((r) => r.request.sessionId).toSet(), {
        smsSession,
        smsNextSession,
      });
      expect(h.repo.receiptSmsConsentFor(smsGroup).recordedRevision, isNull);
      expect(h.repo.receiptSmsConsentFor(smsGroup).needsRefresh, isTrue);
      await expectLater(
        h.repo.setReceiptSmsConsent(smsGroup, optIn: false),
        throwsStateError,
      );
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      await h.repo.setReceiptSmsConsent(smsGroup, optIn: false);
      expect(h.writes, hasLength(3));
      expect(h.writes.last['p_expected_decision_revision'], 1);
      expect(h.current(smsGroup)['opt_in'], isFalse);
      expect(h.current(smsGroup)['decision_revision'], 2);
    },
  );
  test(
    'lost fence ACK reconstructs and retries exact original body without creating a UUID or incrementing again',
    () async {
      final h = await harness();
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      h.loseReply = true;
      await expectLater(
        h.repo.setReceiptSmsConsent(smsGroup, optIn: true),
        throwsA(isA<TimeoutException>()),
      );
      await h.login(smsUser, smsNextSession);
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      h.loseReply = true;
      await expectLater(
        h.repo.withdrawReceiptSmsAndRecover(smsGroup),
        throwsA(isA<TimeoutException>()),
      );
      final original = {...h.writes.last};
      expect(h.current(smsGroup)['decision_revision'], 2);
      h.reconstruct();
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      expect(
        h.repo.receiptSmsConsentFor(smsGroup).recovery.pending,
        hasLength(2),
      );
      await expectLater(
        h.repo.withdrawReceiptSmsAndRecover(smsGroup),
        throwsStateError,
      );
      await h.repo.retryReceiptSmsConsent(smsGroup);
      expect(h.writes.last, original);
      expect(h.current(smsGroup)['decision_revision'], 2);
      final recovered = await h.store.read(
        userId: smsUser,
        collectionId: smsGroup,
      );
      expect(recovered.pending, isEmpty);
      expect(recovered.superseded, hasLength(1));
      expect(recovered.superseded.single.request.sessionId, smsSession);
      expect(h.repo.receiptSmsConsentFor(smsGroup).needsRefresh, isTrue);
    },
  );
  test(
    'another relogin can explicitly fence both retained identities without replacing either before HTTP',
    () async {
      final h = await harness();
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      h.loseReply = true;
      await expectLater(
        h.repo.setReceiptSmsConsent(smsGroup, optIn: true),
        throwsA(isA<TimeoutException>()),
      );
      await h.login(smsUser, smsNextSession);
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      h.loseReply = true;
      await expectLater(
        h.repo.withdrawReceiptSmsAndRecover(smsGroup),
        throwsA(isA<TimeoutException>()),
      );
      final older = (await h.store.read(
        userId: smsUser,
        collectionId: smsGroup,
      )).pending.map((r) => r.toJson()).toList();
      const third = 'd2000000-0000-4000-8000-000000000003';
      await h.login(smsUser, third);
      h.reconstruct();
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      final gate = Completer<void>();
      h.sessionWriteGates[third] = gate;
      final recovering = h.repo.withdrawReceiptSmsAndRecover(smsGroup);
      await _until(() => h.writes.length == 3);
      final retained = (await h.store.read(
        userId: smsUser,
        collectionId: smsGroup,
      )).pending;
      expect(retained, hasLength(3));
      for (final old in older) {
        expect(
          retained
              .singleWhere((r) => r.requestId == old['request_id'])
              .toJson(),
          old,
        );
      }
      gate.complete();
      await recovering;
      final current = await h.store.read(
        userId: smsUser,
        collectionId: smsGroup,
      );
      expect(current.pending, isEmpty);
      expect(current.superseded, hasLength(2));
      expect(h.current(smsGroup)['decision_revision'], 3);
      expect(h.current(smsGroup)['opt_in'], isFalse);
    },
  );
  test(
    'equal decision head or matching current choice cannot supersede an unknown earlier request',
    () async {
      final h = await harness();
      await h.store.claim(pending(1));
      await h.login(smsUser, smsNextSession);
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      final before = await h.store.path(smsUser).readAsString();
      await expectLater(
        h.repo.supersedeReceiptSmsRequests(smsGroup),
        throwsStateError,
      );
      expect(await h.store.path(smsUser).readAsString(), before);
      expect(h.writes, isEmpty);
      await expectLater(
        h.repo.setReceiptSmsConsent(smsGroup, optIn: false),
        throwsStateError,
      );
    },
  );
  test(
    'recovery history capacity is reserved before HTTP and never silently trims another identity',
    () async {
      final h = await harness();
      final original = pending(1);
      final history = List.generate(
        31,
        (i) => ReceiptSmsSuperseded(
          pending(i + 100, group: smsGroupB, choice: false),
          1,
        ),
      );
      final seeded = ReceiptSmsRecoveryState(
        pending: [original],
        superseded: history,
      );
      await h.store
          .path(smsUser)
          .writeAsString(jsonEncode(seeded.toJson()), flush: true);
      await h.login(smsUser, smsNextSession);
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      final before = await h.store.path(smsUser).readAsString();
      await expectLater(
        h.repo.withdrawReceiptSmsAndRecover(smsGroup),
        throwsStateError,
      );
      expect(h.writes, isEmpty);
      expect(await h.store.path(smsUser).readAsString(), before);
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      expect(
        h.repo.receiptSmsConsentFor(smsGroup).recovery.pending.single.requestId,
        original.requestId,
      );
    },
  );
  test(
    'a native write with unknown acknowledgement never dispatches and preserves original custody through reconstruction',
    () async {
      final h = await harness();
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      h.store.failAfterClaimWrite = true;
      await expectLater(
        h.repo.setReceiptSmsConsent(smsGroup, optIn: true),
        throwsA(isA<Exception>()),
      );
      expect(h.writes, isEmpty);
      final original = (await h.store.read(
        userId: smsUser,
        collectionId: smsGroup,
      )).pending.single;
      h.reconstruct();
      await h.repo.refreshReceiptSmsConsent(smsGroup);
      expect(
        h.repo.receiptSmsConsentFor(smsGroup).pending!.toJson(),
        original.toJson(),
      );
      await expectLater(
        h.repo.setReceiptSmsConsent(smsGroup, optIn: false),
        throwsStateError,
      );
      expect(h.writes, isEmpty);
    },
  );
  test(
    'unsafe or missing expected decision metadata fails closed rather than inventing a revision',
    () {
      final original = pending(1).toJson();
      expect(
        PendingReceiptSmsRequest.decode(original).expectedDecisionRevision,
        0,
      );
      for (final bad in [true, 0.0, '0', -1, 9007199254740991]) {
        expect(
          () => PendingReceiptSmsRequest.decode({
            ...original,
            'expected_decision_revision': bad,
          }),
          throwsFormatException,
        );
      }
      final missing = {...original}..remove('expected_decision_revision');
      expect(
        () => PendingReceiptSmsRequest.decode(missing),
        throwsFormatException,
      );
      expect(
        PendingReceiptSmsRequest.decode(
          pending(2, decision: 9007199254740990).toJson(),
        ).expectedDecisionRevision,
        9007199254740990,
      );
    },
  );
  test(
    'native bridge strictly binds dual revisions, complete and supersede custody',
    () async {
      const channel = MethodChannel('collect/receipt_sms_pending');
      final calls = <MethodCall>[];
      final request = pending(1),
          fence = pending(2, session: smsNextSession, choice: false);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return switch (call.method) {
              'complete' => const ReceiptSmsRecoveryState().toJson(),
              'supersede' => ReceiptSmsRecoveryState(
                superseded: [ReceiptSmsSuperseded(request, 1)],
              ).toJson(),
              'claimWithdrawalFence' => ReceiptSmsRecoveryState(
                pending: [request, fence],
              ).toJson(),
              _ => ReceiptSmsRecoveryState(pending: [request]).toJson(),
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      const store = NativeReceiptSmsPendingStore();
      expect(
        (await store.claim(request)).pending.single.sameRequest(request),
        isTrue,
      );
      expect(
        (await store.read(
          userId: smsUser,
          collectionId: smsGroup,
        )).pending.single.requestId,
        request.requestId,
      );
      expect(
        (await store.claim(fence, withdrawalFence: true)).pending,
        hasLength(2),
      );
      expect((await store.complete(request, 1)).pending, isEmpty);
      expect(
        (await store.supersede(
          userId: smsUser,
          collectionId: smsGroup,
          knownRequests: [request],
          observedDecisionRevision: 1,
        )).superseded.single.request.requestId,
        request.requestId,
      );
      expect(calls.map((c) => c.method), [
        'claim',
        'read',
        'claimWithdrawalFence',
        'complete',
        'supersede',
      ]);
      expect((calls[2].arguments as Map)['request'], fence.toJson());
      expect((calls[4].arguments as Map)['known_requests'], [request.toJson()]);
      expect(request.rpcParameters.keys.toSet(), {
        'p_collection_id',
        'p_expected_revision',
        'p_expected_decision_revision',
        'p_opt_in',
        'p_request_id',
      });
      final serialized = jsonEncode(calls.map((c) => c.arguments).toList());
      for (final key in ['phone', 'token', 'body', 'destination']) {
        expect(serialized, isNot(contains(key)));
      }
    },
  );
}

PendingReceiptSmsRequest pending(
  int id, {
  String session = smsSession,
  String group = smsGroup,
  bool choice = true,
  int revision = 0,
  int decision = 0,
}) => PendingReceiptSmsRequest(
  userId: smsUser,
  sessionId: session,
  collectionId: group,
  requestId: 'd5000000-0000-4000-8000-${id.toString().padLeft(12, '0')}',
  expectedRevision: revision,
  expectedDecisionRevision: decision,
  optIn: choice,
);
