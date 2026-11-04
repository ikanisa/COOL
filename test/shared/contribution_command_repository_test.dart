import 'dart:async';
import 'dart:convert';

import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:collect_app/core/payments/contribution_command_journal.dart';
import 'package:collect_app/core/supabase/collect_supabase_configuration.dart';
import 'package:collect_app/core/security/contribution_command_storage_contract.dart';
import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/contribution_command_values.dart';

const _draft = PaymentIntentDraft(
  collectionId: commandGroupId,
  amountRwf: 5000,
);
const _nextSession = '20000000-0000-0000-0000-000000000002';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'actual repository persists exact original body before one creation POST and uses separate review',
    () async {
      final h = await _Harness.create();
      h.onCreate = (request) async {
        final rows = await h.journal.read(commandOwner());
        final record = rows.single;
        expect(record.phase, ContributionCommandPhase.dispatchPossible);
        expect(jsonDecode(request.body), record.body.toJson());
        expect(record.originalSessionId, commandSessionId);
        return commandIntentWire();
      };
      final intent = await h.repo.prepareContributionIntent(_draft);
      expect(h.creates, hasLength(1));
      final originalBody = Map<String, dynamic>.from(
        jsonDecode(h.creates.single.body) as Map,
      );
      expect(originalBody.keys.toSet(), {
        'collection',
        'p_expected_amount_rwf',
        'p_sender_phone_hash',
        'p_request_id',
      });
      final checkpoint = (await h.journal.read(commandOwner())).single;
      expect(checkpoint.phase, ContributionCommandPhase.receiptRetained);
      final review = await h.repo.reviewContributionIntent(intent);
      expect(h.reviews, hasLength(1));
      expect(h.creates, hasLength(1));
      final permit = await h.repo.claimContributionHandoff(intent, review);
      expect(
        (await h.journal.read(commandOwner())).single.providerHandoffPossible,
        isTrue,
      );
      expect(permit.consume(), isTrue);
      expect(permit.consume(), isFalse);
      final restarted = h.newRepository();
      expect(
        (await restarted.restoreContributionCommand(
          commandGroupId,
        ))!.body.canonical,
        checkpoint.body.canonical,
      );
      await expectLater(
        restarted.reviewContributionIntent(intent),
        throwsA(isA<ContributionRecoveryRequired>()),
      );
      expect(h.creates, hasLength(1));
    },
  );
  for (final failure in [
    'lost creation response',
    'malformed creation receipt',
  ]) {
    test(
      '$failure retains request and repeated preparation never creates another key',
      () async {
        final h = await _Harness.create();
        h.onCreate = (_) {
          if (failure.startsWith('lost')) {
            throw http.ClientException('Synthetic lost response');
          }
          return commandIntentWire()..['amount_minor'] = 5001;
        };
        await expectLater(
          h.repo.prepareContributionIntent(_draft),
          throwsA(isA<ContributionRecoveryRequired>()),
        );
        final retained = (await h.journal.read(commandOwner())).single;
        await expectLater(
          h.repo.prepareContributionIntent(
            const PaymentIntentDraft(
              collectionId: commandGroupId,
              amountRwf: 8000,
            ),
          ),
          throwsA(isA<ContributionRecoveryRequired>()),
        );
        expect(h.creates, hasLength(1));
        expect(
          (await h.journal.read(commandOwner())).single.body.canonical,
          retained.body.canonical,
        );
        final observed = await h.repo.checkContributionCommand(
          retained.body.requestId,
        );
        expect(observed.intentId, isNull);
        expect(h.lookups, hasLength(1));
        expect(
          jsonDecode(h.lookups.single.body)['p_original_body'],
          retained.body.toJson(),
        );
        expect(h.creates, hasLength(1));
        expect(h.repo.state.paymentIntents, isEmpty);
      },
    );
  }
  for (final sender in [
    '',
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  ]) {
    test(
      'creation receipt with invalid sender binding remains unresolved',
      () async {
        final h = await _Harness.create();
        h.onCreate = (_) => commandIntentWire(senderHash: sender);
        await expectLater(
          h.repo.prepareContributionIntent(_draft),
          throwsA(isA<ContributionRecoveryRequired>()),
        );
        final retained = (await h.journal.read(commandOwner())).single;
        expect(retained.phase, ContributionCommandPhase.dispatchPossible);
        expect(retained.providerHandoffPossible, isFalse);
        expect(h.repo.state.paymentIntents, isEmpty);
      },
    );
  }
  for (final failure in [
    'prepare ACK',
    'dispatch ACK',
    'receipt ACK',
    'handoff ACK',
  ]) {
    test(
      'lost local $failure cannot grant creation or provider launch',
      () async {
        final h = await _Harness.create();
        if (failure == 'prepare ACK') h.storage.loseNextAcknowledgement = true;
        if (failure == 'dispatch ACK') h.storage.loseAtCommit = 2;
        if (failure == 'receipt ACK') h.storage.loseAtCommit = 3;
        if (failure != 'handoff ACK') {
          await expectLater(
            h.repo.prepareContributionIntent(_draft),
            failure == 'prepare ACK'
                ? throwsStateError
                : throwsA(isA<ContributionRecoveryRequired>()),
          );
          expect(h.creates, hasLength(failure == 'receipt ACK' ? 1 : 0));
          expect(
            await h.repo.restoreContributionCommand(commandGroupId),
            isNotNull,
          );
          await expectLater(
            h.repo.prepareContributionIntent(_draft),
            throwsA(isA<ContributionRecoveryRequired>()),
          );
          expect(h.creates, hasLength(failure == 'receipt ACK' ? 1 : 0));
        } else {
          final intent = await h.repo.prepareContributionIntent(_draft);
          final review = await h.repo.reviewContributionIntent(intent);
          h.storage.loseNextAcknowledgement = true;
          await expectLater(
            h.repo.claimContributionHandoff(intent, review),
            throwsStateError,
          );
          expect(
            (await h.journal.read(
              commandOwner(),
            )).single.providerHandoffPossible,
            isTrue,
          );
          await expectLater(
            h.repo.reviewContributionIntent(intent),
            throwsA(isA<ContributionRecoveryRequired>()),
          );
        }
      },
    );
  }
  for (final change in [
    'receiver',
    'old create receipt',
    'unavailable',
    'wrong session',
  ]) {
    test(
      'current review $change refuses handoff without new creation',
      () async {
        final h = await _Harness.create();
        final intent = await h.repo.prepareContributionIntent(_draft);
        h.onReview = (_) {
          if (change == 'unavailable') {
            throw http.ClientException('Synthetic current review unavailable');
          }
          if (change == 'old create receipt') return commandIntentWire();
          return commandReviewWire(
            receiver: change == 'receiver' ? '0788999999' : '0788123456',
            session: change == 'wrong session'
                ? _nextSession
                : commandSessionId,
          );
        };
        await expectLater(
          h.repo.reviewContributionIntent(intent),
          throwsA(
            anyOf(
              isA<ContributionReviewChanged>(),
              isA<FormatException>(),
              isA<Exception>(),
            ),
          ),
        );
        expect(h.creates, hasLength(1));
        expect(
          (await h.journal.read(commandOwner())).single.providerHandoffPossible,
          isFalse,
        );
      },
    );
  }
  for (final change in ['receiver', 'status', 'revision', 'sender']) {
    test(
      'change to $change during the durable handoff claim denies launch',
      () async {
        final h = await _Harness.create();
        final intent = await h.repo.prepareContributionIntent(_draft);
        final review = await h.repo.reviewContributionIntent(intent);
        final entered = Completer<void>();
        final release = Completer<void>();
        h.storage.afterCommit = () async {
          entered.complete();
          await release.future;
        };
        final claim = h.repo.claimContributionHandoff(intent, review);
        final denied = expectLater(
          claim,
          throwsA(isA<ContributionReviewChanged>()),
        );
        await entered.future;
        h.onReview = (_) => commandReviewWire(
          receiver: change == 'receiver' ? '0788999999' : '0788123456',
          status: change == 'status' ? 'cancelled' : 'pending',
          senderHash: change == 'sender'
              ? 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
              : null,
        )..['collection_revision'] = change == 'revision' ? 3 : 2;
        release.complete();
        await denied;
        expect(h.reviews, hasLength(2));
        expect(
          (await h.journal.read(commandOwner())).single.providerHandoffPossible,
          isTrue,
        );
        expect(h.creates, hasLength(1));
      },
    );
  }
  test('profile change during the handoff claim denies the permit', () async {
    final h = await _Harness.create();
    final intent = await h.repo.prepareContributionIntent(_draft);
    final review = await h.repo.reviewContributionIntent(intent);
    final entered = Completer<void>();
    final release = Completer<void>();
    h.storage.afterCommit = () async {
      entered.complete();
      await release.future;
    };
    final claim = h.repo.claimContributionHandoff(intent, review);
    final denied = expectLater(claim, throwsStateError);
    await entered.future;
    h.repo.updateMomoNumber('0788999999');
    release.complete();
    await denied;
    expect(
      (await h.journal.read(commandOwner())).single.providerHandoffPossible,
      isTrue,
    );
    expect(h.creates, hasLength(1));
  });
  test('profile change invalidates an issued but unused permit', () async {
    final h = await _Harness.create();
    final intent = await h.repo.prepareContributionIntent(_draft);
    final review = await h.repo.reviewContributionIntent(intent);
    final permit = await h.repo.claimContributionHandoff(intent, review);
    h.repo.updateMomoNumber('0788999999');
    expect(permit.consume(), isFalse);
  });
  for (final change in [
    'receiver',
    'network',
    'label',
    'membership',
    'missing group',
    'duplicate group',
    'missing intent',
    'duplicate intent',
    'cancelled',
    'payment received',
    'credited',
    'needs review',
    'provider reference',
    'stale cache',
    'loading',
    'missing sync',
    'financial uncertainty',
  ]) {
    test(
      'new $change observation during final review denies handoff and retains custody',
      () async {
        final h = await _Harness.create();
        final intent = await h.repo.prepareContributionIntent(_draft);
        final review = await h.repo.reviewContributionIntent(intent);
        final original = (await h.journal.read(commandOwner())).single;
        final entered = Completer<void>(), release = Completer<void>();
        h.onReview = (_) async {
          entered.complete();
          await release.future;
          return commandReviewWire();
        };
        final pending = h.repo.claimContributionHandoff(intent, review);
        final denied = expectLater(
          pending,
          throwsA(isA<ContributionReviewChanged>()),
        );
        await entered.future;
        h.repo.observe(change);
        release.complete();
        await denied;
        final retained = (await h.journal.read(commandOwner())).single;
        expect(retained.providerHandoffPossible, isTrue);
        expect(retained.body.canonical, original.body.canonical);
        expect(retained.originalSessionId, original.originalSessionId);
        expect(h.creates, hasLength(1));
        expect(h.reviews, hasLength(2));
      },
    );
  }
  for (final change in [
    'receiver',
    'membership',
    'payment received',
    'stale cache',
  ]) {
    test('new $change observation invalidates an issued permit', () async {
      final h = await _Harness.create();
      final intent = await h.repo.prepareContributionIntent(_draft);
      final review = await h.repo.reviewContributionIntent(intent);
      final permit = await h.repo.claimContributionHandoff(intent, review);
      h.repo.observe(change);
      expect(permit.consume(), isFalse);
      expect(
        (await h.journal.read(commandOwner())).single.providerHandoffPossible,
        isTrue,
      );
      expect(h.creates, hasLength(1));
    });
  }
  test(
    'a contradictory observation cannot be erased by changing back before review completes',
    () async {
      final h = await _Harness.create();
      final intent = await h.repo.prepareContributionIntent(_draft);
      final review = await h.repo.reviewContributionIntent(intent);
      final entered = Completer<void>(), release = Completer<void>();
      h.onReview = (_) async {
        entered.complete();
        await release.future;
        return commandReviewWire();
      };
      final pending = h.repo.claimContributionHandoff(intent, review);
      final denied = expectLater(
        pending,
        throwsA(isA<ContributionReviewChanged>()),
      );
      await entered.future;
      final original = h.repo.state;
      h.repo.observe('receiver');
      h.repo.restoreObservation(original);
      release.complete();
      await denied;
      expect(
        (await h.journal.read(commandOwner())).single.providerHandoffPossible,
        isTrue,
      );
    },
  );
  test(
    'known stale relevant data denies before durable handoff claim',
    () async {
      final h = await _Harness.create();
      final intent = await h.repo.prepareContributionIntent(_draft);
      final review = await h.repo.reviewContributionIntent(intent);
      h.repo.observe('stale cache');
      await expectLater(
        h.repo.claimContributionHandoff(intent, review),
        throwsA(isA<ContributionReviewChanged>()),
      );
      expect(
        (await h.journal.read(commandOwner())).single.providerHandoffPossible,
        isFalse,
      );
      expect(h.reviews, hasLength(1));
    },
  );
  test(
    'interrupted financial observation denies before durable handoff claim',
    () async {
      final h = await _Harness.create();
      final intent = await h.repo.prepareContributionIntent(_draft);
      final review = await h.repo.reviewContributionIntent(intent);
      h.repo.observe('financial uncertainty');
      await expectLater(
        h.repo.claimContributionHandoff(intent, review),
        throwsA(isA<ContributionReviewChanged>()),
      );
      expect(
        (await h.journal.read(commandOwner())).single.providerHandoffPossible,
        isFalse,
      );
      expect(h.reviews, hasLength(1));
    },
  );
  test(
    'route change during durable claim denies and retains the original recovery record',
    () async {
      final h = await _Harness.create();
      final intent = await h.repo.prepareContributionIntent(_draft);
      final review = await h.repo.reviewContributionIntent(intent);
      final original = (await h.journal.read(commandOwner())).single;
      final entered = Completer<void>(), release = Completer<void>();
      h.storage.afterCommit = () async {
        entered.complete();
        await release.future;
      };
      final pending = h.repo.claimContributionHandoff(intent, review);
      final denied = expectLater(pending, throwsStateError);
      await entered.future;
      h.repo.observe('membership');
      release.complete();
      await denied;
      final retained = (await h.journal.read(commandOwner())).single;
      expect(retained.providerHandoffPossible, isTrue);
      expect(retained.body.canonical, original.body.canonical);
      expect(retained.originalSessionId, original.originalSessionId);
      expect(h.creates, hasLength(1));
      expect(h.reviews, hasLength(1));
    },
  );
  test(
    'null, omitted and literal fallback labels retain separate route provenance',
    () {
      final observedNull = _collectionWithLabel(null);
      final omitted = _collectionWithLabel(null, omitted: true);
      final literal = _collectionWithLabel('Primary MoMo receiver');
      expect(observedNull.receiverDisplayLabel, 'Primary MoMo receiver');
      expect(observedNull.receiverRouteLabel, '');
      expect(observedNull.copyWith(title: 'Updated').receiverRouteLabel, '');
      expect(omitted.receiverRouteLabel, isNull);
      expect(omitted.copyWith(title: 'Updated').receiverRouteLabel, isNull);
      expect(literal.receiverRouteLabel, 'Primary MoMo receiver');
      expect(
        observedNull
            .copyWith(receiverDisplayLabel: 'Primary MoMo receiver')
            .receiverRouteLabel,
        '',
      );
      expect(
        omitted
            .copyWith(receiverDisplayLabel: 'Primary MoMo receiver')
            .receiverRouteLabel,
        isNull,
      );
      expect(
        observedNull
            .copyWith(receiverDisplayLabel: 'Changed')
            .receiverRouteLabel,
        isNull,
      );
      expect(
        observedNull
            .copyWith(
              receiverDisplayLabel: 'Changed',
              receiverRouteLabel: 'Changed',
            )
            .receiverRouteLabel,
        'Changed',
      );
    },
  );
  test(
    'observed null route label permits an unchanged server review',
    () async {
      final h = await _Harness.create();
      h.repo.replaceGroup(_collectionWithLabel(null));
      h.onCreate = (_) => commandIntentWire()..['receiver_label'] = '';
      h.onReview = (_) {
        final wire = commandReviewWire();
        (wire['intent'] as Map<String, dynamic>)['receiver_label'] = '';
        return wire;
      };
      final intent = await h.repo.prepareContributionIntent(_draft);
      final review = await h.repo.reviewContributionIntent(intent);
      final permit = await h.repo.claimContributionHandoff(intent, review);
      expect(permit.consume(), isTrue);
    },
  );
  test(
    'explicit fallback label observed after null invalidates issued permit',
    () async {
      final h = await _Harness.create();
      h.repo.replaceGroup(_collectionWithLabel(null));
      h.onCreate = (_) => commandIntentWire()..['receiver_label'] = '';
      h.onReview = (_) {
        final wire = commandReviewWire();
        (wire['intent'] as Map<String, dynamic>)['receiver_label'] = '';
        return wire;
      };
      final intent = await h.repo.prepareContributionIntent(_draft);
      final review = await h.repo.reviewContributionIntent(intent);
      final permit = await h.repo.claimContributionHandoff(intent, review);
      h.repo.replaceGroup(_collectionWithLabel('Primary MoMo receiver'));
      expect(permit.consume(), isFalse);
      expect(
        (await h.journal.read(commandOwner())).single.providerHandoffPossible,
        isTrue,
      );
    },
  );
  test('missing route-label provenance denies before handoff claim', () async {
    final h = await _Harness.create();
    h.repo.replaceGroup(_collectionWithLabel(null, omitted: true));
    h.onCreate = (_) => commandIntentWire()..['receiver_label'] = '';
    h.onReview = (_) {
      final wire = commandReviewWire();
      (wire['intent'] as Map<String, dynamic>)['receiver_label'] = '';
      return wire;
    };
    final intent = await h.repo.prepareContributionIntent(_draft);
    final review = await h.repo.reviewContributionIntent(intent);
    await expectLater(
      h.repo.claimContributionHandoff(intent, review),
      throwsA(isA<ContributionReviewChanged>()),
    );
    expect(
      (await h.journal.read(commandOwner())).single.providerHandoffPossible,
      isFalse,
    );
  });
  test(
    'unrelated error does not replace valid relevant observations or server review',
    () async {
      final h = await _Harness.create();
      final intent = await h.repo.prepareContributionIntent(_draft);
      final review = await h.repo.reviewContributionIntent(intent);
      final entered = Completer<void>(), release = Completer<void>();
      h.onReview = (_) async {
        entered.complete();
        await release.future;
        return commandReviewWire();
      };
      final pending = h.repo.claimContributionHandoff(intent, review);
      await entered.future;
      h.repo.observe('unrelated error');
      release.complete();
      final permit = await pending;
      expect(permit.consume(), isTrue);
      expect(h.reviews, hasLength(2));
      expect(h.creates, hasLength(1));
    },
  );
  test('sign-out start invalidates an issued but unused permit', () async {
    final h = await _Harness.create();
    final intent = await h.repo.prepareContributionIntent(_draft);
    final review = await h.repo.reviewContributionIntent(intent);
    final permit = await h.repo.claimContributionHandoff(intent, review);
    final logout = h.repo.signOut();
    await h.sms.stopEntered.future;
    try {
      expect(permit.consume(), isFalse);
      expect(h.creates, hasLength(1));
      expect(
        (await h.journal.read(commandOwner())).single.providerHandoffPossible,
        isTrue,
      );
    } finally {
      h.sms.stopReply.complete(true);
      await logout;
    }
  });
  test('sign-out during the durable handoff claim denies the permit', () async {
    final h = await _Harness.create();
    final intent = await h.repo.prepareContributionIntent(_draft);
    final review = await h.repo.reviewContributionIntent(intent);
    final entered = Completer<void>();
    final release = Completer<void>();
    h.storage.afterCommit = () async {
      entered.complete();
      await release.future;
    };
    final claim = h.repo.claimContributionHandoff(intent, review);
    final denied = expectLater(claim, throwsStateError);
    await entered.future;
    final logout = h.repo.signOut();
    await h.sms.stopEntered.future;
    try {
      release.complete();
      await denied;
      expect(h.creates, hasLength(1));
      expect(
        (await h.journal.read(commandOwner())).single.providerHandoffPossible,
        isTrue,
      );
    } finally {
      if (!release.isCompleted) release.complete();
      h.sms.stopReply.complete(true);
      await logout;
    }
  });
  test(
    'unavailable final review retains the handoff claim without a permit',
    () async {
      final h = await _Harness.create();
      final intent = await h.repo.prepareContributionIntent(_draft);
      final review = await h.repo.reviewContributionIntent(intent);
      h.onReview = (_) => throw http.ClientException('Synthetic lost review');
      await expectLater(
        h.repo.claimContributionHandoff(intent, review),
        throwsA(isA<Exception>()),
      );
      expect(
        (await h.journal.read(commandOwner())).single.providerHandoffPossible,
        isTrue,
      );
      expect(h.creates, hasLength(1));
    },
  );
  test('a final review permit expires before a delayed handoff', () async {
    final h = await _Harness.create();
    final intent = await h.repo.prepareContributionIntent(_draft);
    final review = await h.repo.reviewContributionIntent(intent);
    final permit = await h.repo.claimContributionHandoff(intent, review);
    await Future<void>.delayed(const Duration(milliseconds: 5100));
    expect(permit.consume(), isFalse);
    expect(
      (await h.journal.read(commandOwner())).single.providerHandoffPossible,
      isTrue,
    );
  });
  test(
    'replacement session may check original receipt, never review or rebind it',
    () async {
      final h = await _Harness.create();
      final intent = await h.repo.prepareContributionIntent(_draft);
      final original = (await h.journal.read(commandOwner())).single;
      await h.login(commandOwnerId, commandAuthId, _nextSession);
      h.onLookup = (_) => commandObservationWire(
        original,
        intentId: commandIntentId,
        status: 'cancelled',
      );
      final observed = await h.repo.checkContributionCommand(
        original.body.requestId,
      );
      expect(observed.originalSessionId, commandSessionId);
      expect(observed.observedStatus, 'cancelled');
      await expectLater(
        h.repo.reviewContributionIntent(intent),
        throwsA(isA<ContributionRecoveryRequired>()),
      );
      await expectLater(
        h.repo.prepareContributionIntent(_draft),
        throwsA(isA<ContributionRecoveryRequired>()),
      );
      expect(h.creates, hasLength(1));
    },
  );
  test(
    'late creation ACK after A B A cannot publish but original owner can inspect custody',
    () async {
      final h = await _Harness.create();
      final entered = Completer<void>(), reply = Completer<Object?>();
      h.onCreate = (_) {
        entered.complete();
        return reply.future;
      };
      final pending = h.repo.prepareContributionIntent(_draft);
      final denied = expectLater(
        pending,
        throwsA(isA<ContributionRecoveryRequired>()),
      );
      await entered.future;
      await h.login(
        '10000000-0000-0000-0000-000000000002',
        '11000000-0000-0000-0000-000000000002',
        _nextSession,
      );
      await h.login(commandOwnerId, commandAuthId, commandSessionId);
      reply.complete(commandIntentWire());
      await denied;
      expect(h.repo.state.paymentIntents, isEmpty);
      expect(
        (await h.repo.restoreContributionCommand(
          commandGroupId,
        ))!.originalSessionId,
        commandSessionId,
      );
      expect(h.creates, hasLength(1));
    },
  );
  test('lost authority and unreadable custody fail before create', () async {
    final h = await _Harness.create();
    h.storage.failRead = true;
    await expectLater(
      h.repo.prepareContributionIntent(_draft),
      throwsStateError,
    );
    expect(h.creates, isEmpty);
    h.storage.failRead = false;
    h.onWitness = (_) =>
        commandWitnessWire()
          ..['issuer'] = 'https://foreign.supabase.co/auth/v1';
    await expectLater(
      h.repo.prepareContributionIntent(_draft),
      throwsFormatException,
    );
    expect(h.creates, isEmpty);
  });

  test(
    'sign-out start fences a pending witness before custody or dispatch',
    () async {
      final h = await _Harness.create();
      final entered = Completer<void>();
      final witness = Completer<Object?>();
      h.onWitness = (_) {
        entered.complete();
        return witness.future;
      };
      final preparing = h.repo.prepareContributionIntent(_draft);
      final denied = expectLater(preparing, throwsStateError);
      await entered.future;
      final logout = h.repo.signOut();
      await h.sms.stopEntered.future;
      witness.complete(commandWitnessWire());
      await denied;
      expect(h.creates, isEmpty);
      expect(await h.journal.read(commandOwner()), isEmpty);
      h.sms.stopReply.complete(true);
      await logout;
    },
  );
}

typedef _Respond = FutureOr<Object?> Function(http.Request);

class _Store extends MemoryContributionStore {
  int? loseAtCommit;
  Future<void> Function()? afterCommit;
  @override
  Future<ContributionStoreCasResult> compareAndSet(
    String partitionId,
    int expectedRevision,
    String payload,
  ) async {
    if (loseAtCommit == commits + 1) loseNextAcknowledgement = true;
    final result = await super.compareAndSet(
      partitionId,
      expectedRevision,
      payload,
    );
    final onCommit = afterCommit;
    afterCommit = null;
    if (result.committed && onCommit != null) await onCommit();
    return result;
  }
}

class _Sms extends SmsAccessChannel {
  final stopEntered = Completer<void>();
  final stopReply = Completer<bool>();

  @override
  Future<bool> setEnabled(bool enabled, {String? ownerUserId}) {
    if (!stopEntered.isCompleted) stopEntered.complete();
    return stopReply.future;
  }
}

class _Harness {
  _Harness(this.client, this.storage, this.journal, this.requests, this.sms);
  final CollectCloudflareClient client;
  final _Store storage;
  final ContributionCommandJournal journal;
  final List<http.Request> requests;
  final _Sms sms;
  late _Repository repo;
  late _Respond onCreate, onReview, onLookup, onWitness;
  final repositories = <_Repository>[];
  String currentSession = commandSessionId,
      currentOwner = commandOwnerId,
      currentAuth = commandAuthId;
  List<http.Request> _for(String operation) =>
      requests.where((r) => r.url.path.endsWith('/$operation')).toList();
  List<http.Request> get creates => _for('create_contribution_intent');
  List<http.Request> get reviews =>
      _for('review_current_member_contribution_intent_v1');
  List<http.Request> get lookups =>
      _for('get_current_member_contribution_command_v1');
  static Future<_Harness> create() async {
    final requests = <http.Request>[];
    final config = CollectSupabaseConfiguration.fromEnvironment(
      const AppEnv(
        apiUrl: '',
        publicUrl: '',
        adminAppUrl: '',
        enableSmsReader: false,
        enableAndroidSmsAccess: false,
        enableAdminPanel: false,
        enableAdminDevTools: false,
        authCaptchaEnabled: false,
        authCaptchaProvider: '',
        authCaptchaSiteKey: '',
        backend: 'supabase',
        supabaseUrl: commandProject,
        supabasePublishableKey: 'sb_publishable_syntheticPublicKey1234',
      ),
    );
    late _Harness h;
    final client = CollectCloudflareClient(
      config.api.origin,
      supabaseConfiguration: config,
      httpClient: MockClient((request) async {
        requests.add(request);
        final Object? value = switch (request.url.path.split('/').last) {
          'create_contribution_intent' => await h.onCreate(request),
          'review_current_member_contribution_intent_v1' => await h.onReview(
            request,
          ),
          'get_current_member_contribution_command_v1' => await h.onLookup(
            request,
          ),
          'get_current_member_contribution_session_v1' => await h.onWitness(
            request,
          ),
          'record_sms_access_consent' => null,
          'logout' => <String, dynamic>{},
          _ => throw StateError('Unexpected synthetic HTTP operation'),
        };
        return http.Response(
          jsonEncode(value),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    final storage = _Store(),
        journal = ContributionCommandJournal(storage: storage);
    h = _Harness(client, storage, journal, requests, _Sms());
    h.onCreate = (_) => commandIntentWire();
    h.onReview = (_) => commandReviewWire(session: h.currentSession);
    h.onWitness = (_) => commandWitnessWire(
      session: h.currentSession,
      owner: h.currentOwner,
      auth: h.currentAuth,
    );
    h.onLookup = (request) {
      final body = jsonDecode(request.body) as Map;
      return {
        'contract_version': 1,
        'request_id': body['p_original_request_id'],
        'original_session_id': body['p_original_session_id'],
        'collection_id': body['p_collection_id'],
        'body_sha256': ContributionCommandBody.fromJson(
          body['p_original_body'],
        ).sha256,
        'command_status': 'unknown',
        'observed_at': DateTime.now().toUtc().toIso8601String(),
        'external_payment': 'unknown',
        'retry_authorized': false,
        'launch_authorized': false,
        'observed_intent': null,
      };
    };
    await h.login(commandOwnerId, commandAuthId, commandSessionId);
    h.repo = h.newRepository();
    addTearDown(() async {
      for (final r in h.repositories) {
        r.dispose();
      }
      await client.dispose();
    });
    return h;
  }

  _Repository newRepository() {
    final r = _Repository(client, journal, sms);
    repositories.add(r);
    return r;
  }

  Future<void> login(String owner, String auth, String session) async {
    currentOwner = owner;
    currentAuth = auth;
    currentSession = session;
    String part(Object value) =>
        base64UrlEncode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final token =
        '${part({'alg': 'ES256'})}.${part({'sub': auth, 'iss': '$commandProject/auth/v1', 'aud': 'authenticated', 'role': 'authenticated', 'session_id': session, 'exp': 4102444800})}.fixture';
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': token,
        'refresh_token': 'synthetic-$session',
        'token_type': 'bearer',
        'user': {'id': owner, 'auth_user_id': auth, 'aud': 'authenticated'},
      }),
    );
    await Future<void>.delayed(Duration.zero);
    // The current auth lifecycle clears financial state immediately and only
    // restores it after the owner/cache fences complete. Await that real
    // transition rather than assuming a single event-loop turn is sufficient.
    for (final repository in repositories) {
      var attempts = 0;
      while (repository.state.currentProfile?.id != owner && attempts++ < 200) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(repository.state.currentProfile?.id, owner);
    }
  }
}

class _Repository extends CollectRepository {
  _Repository(
    this.client,
    ContributionCommandJournal journal,
    SmsAccessChannel sms,
  ) : super.fixture(
        backend: client,
        smsAccessChannel: sms,
        contributionCommandJournal: journal,
        initialState: _state(client.auth.currentUser!.id),
      );
  final CollectCloudflareClient client;
  void updateMomoNumber(String number) {
    state = state.copyWith(
      currentProfile: state.currentProfile!.copyWith(momoNumber: number),
    );
  }

  void restoreObservation(CollectState original) => state = original;
  void replaceGroup(CollectCollection group) =>
      state = state.copyWith(collections: [group]);

  void observe(String change) {
    final group = state.collections.single;
    final intent = state.paymentIntents.single;
    switch (change) {
      case 'receiver':
        state = state.copyWith(
          collections: [group.copyWith(receiverMomoNumber: '0788999999')],
        );
      case 'network':
        state = state.copyWith(
          collections: [group.copyWith(receiverNetwork: 'airtel_money')],
        );
      case 'label':
        state = state.copyWith(
          collections: [
            group.copyWith(receiverDisplayLabel: 'Changed receiver'),
          ],
        );
      case 'membership':
        state = state.copyWith(
          collections: [group.copyWith(isCurrentUserMember: false)],
        );
      case 'missing group':
        state = state.copyWith(collections: []);
      case 'duplicate group':
        state = state.copyWith(collections: [group, group]);
      case 'missing intent':
        state = state.copyWith(paymentIntents: []);
      case 'duplicate intent':
        state = state.copyWith(paymentIntents: [intent, intent]);
      case 'cancelled':
        state = state.copyWith(
          paymentIntents: [
            PaymentIntentModel.fromJson(commandIntentWire(status: 'cancelled')),
          ],
        );
      case 'payment received':
        state = state.copyWith(
          paymentIntents: [
            PaymentIntentModel.fromJson(
              commandIntentWire()..addAll({
                'confirmation_status': 'payment_received',
                'payment_id': 'payment',
              }),
            ),
          ],
        );
      case 'credited':
        state = state.copyWith(
          paymentIntents: [
            PaymentIntentModel.fromJson(
              commandIntentWire()..addAll({
                'confirmation_status': 'credited',
                'payment_id': 'payment',
                'contribution_entry_id': 'entry',
                'credited_amount_rwf': 5000,
                'posted_at': '2026-10-20T00:01:00Z',
              }),
            ),
          ],
        );
      case 'needs review':
        state = state.copyWith(
          paymentIntents: [
            PaymentIntentModel.fromJson(
              commandIntentWire()..['confirmation_status'] = 'needs_review',
            ),
          ],
        );
      case 'provider reference':
        state = state.copyWith(
          paymentIntents: [
            PaymentIntentModel.fromJson(
              commandIntentWire()
                ..['provider_transaction_reference'] = 'synthetic-reference',
            ),
          ],
        );
      case 'stale cache':
        state = state.copyWith(usingStaleCache: true);
      case 'loading':
        state = state.copyWith(isLoading: true);
      case 'missing sync':
        state = state.copyWith(lastSuccessfulSyncAt: null);
      case 'financial uncertainty':
        state = state.copyWith(financialObservationUncertain: true);
      case 'unrelated error':
        state = state.copyWith(
          lastError: 'Synthetic unrelated notification error',
        );
      default:
        throw ArgumentError.value(change);
    }
  }

  @override
  Future<void> loadInitial({bool syncPendingSms = false}) async {
    state = _state(client.auth.currentUser!.id);
  }
}

CollectCollection _collectionWithLabel(String? label, {bool omitted = false}) =>
    CollectCollection.fromJson({
      'id': commandGroupId,
      'slug': 'synthetic-group',
      'creator_user_id': commandOwnerId,
      'title': 'Synthetic group',
      'created_at': '2026-01-01T00:00:00.000Z',
      'receiver_momo_number': '0788123456',
      'receiver_network': 'mtn_momo',
      'is_member': true,
      'is_public': true,
      if (!omitted) 'receiver_display_label': label,
    });

CollectState _state(String actor) => CollectState(
  currentProfile: CollectProfile(
    id: actor,
    publicId: '123456',
    whatsappPhone: '+250788123456',
    countryCode: 'RW',
    currencyCode: 'RWF',
    momoProvider: 'mtn_momo',
    momoNumber: '0788123456',
  ),
  collections: [
    CollectCollection(
      id: commandGroupId,
      slug: 'synthetic-group',
      creatorUserId: actor,
      title: 'Synthetic group',
      description: '',
      createdAt: DateTime.utc(2026),
      receiverMomoNumber: '0788123456',
      receiverDisplayLabel: 'Synthetic receiver',
      receiverNetwork: 'mtn_momo',
      isPublic: true,
    ),
  ],
  paymentIntents: const [],
  contributions: const [],
  lastSuccessfulSyncAt: DateTime.utc(2026),
);
