import 'dart:async';
import 'dart:convert';

import 'package:collect_app/shared/repositories/payment_help_pending_store.dart';
import 'package:collect_app/shared/repositories/payment_help_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const owner = '10000000-0000-0000-0000-000000000001';
const other = '10000000-0000-0000-0000-000000000002';
const group = '30000000-0000-0000-0000-000000000001';
const intent = '70000000-0000-4000-8000-000000000001';
const secondIntent = '70000000-0000-4000-8000-000000000003';
const request = '70000000-0000-4000-8000-000000000002';
const nextRequest = '70000000-0000-4000-8000-000000000004';

PaymentHelpCheckpoint checkpoint({
  String intentId = intent,
  String requestId = request,
  String note = 'Original evidence',
}) => PaymentHelpCheckpoint(
  ownerId: owner,
  collectionId: group,
  intentId: intentId,
  requestId: requestId,
  reference: 'SYNTHETIC-007',
  note: note,
);

class MemoryStorage implements PaymentHelpProtectedStorage {
  final values = <String, String>{};
  Future<void> _tail = Future<void>.value();
  Completer<void>? writing, release;
  bool failWrite = false, failClear = false;
  @override
  Future<T> exclusive<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<String?> read(String ownerId) async => values[ownerId];
  @override
  Future<void> write(String ownerId, String value) async {
    writing?.complete();
    if (release != null) await release!.future;
    if (failWrite) throw StateError('Synthetic storage failure');
    values[ownerId] = value;
  }

  @override
  Future<void> clear(String ownerId) async {
    if (failClear) throw StateError('Synthetic cleanup failure');
    values.remove(ownerId);
  }
}

Future<PaymentHelpCheckpoint?> read(
  PaymentHelpPendingStore store, {
  String intentId = intent,
}) => store.read(ownerId: owner, collectionId: group, intentId: intentId);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'fresh store instance restores immutable request and durable receipt',
    () async {
      final storage = MemoryStorage();
      var store = PaymentHelpPendingStore(storage: storage)..bindOwner(owner);
      final original = await store.retain(checkpoint());
      store = PaymentHelpPendingStore(storage: storage)..bindOwner(owner);
      final restored = (await read(store))!;
      expect(jsonEncode(restored.command), jsonEncode(original.command));
      expect(restored.received, isFalse);
      await store.acknowledge(restored);
      final restarted = PaymentHelpPendingStore(storage: storage)
        ..bindOwner(owner);
      expect((await read(restarted))!.received, isTrue);
      expect((await read(restarted))!.reference, isNull);
      expect((await read(restarted))!.note, isNull);
      expect(() => original.acknowledge().command, throwsStateError);
      expect(
        (await restarted.retain(
          checkpoint(requestId: nextRequest, note: 'Changed draft'),
        )).requestId,
        request,
      );
    },
  );

  test(
    'parallel route claims retain one first body across store instances',
    () async {
      final storage = MemoryStorage();
      final first = PaymentHelpPendingStore(storage: storage)..bindOwner(owner);
      final second = PaymentHelpPendingStore(storage: storage)
        ..bindOwner(owner);
      final results = await Future.wait([
        first.retain(checkpoint()),
        second.retain(
          checkpoint(requestId: nextRequest, note: 'Conflicting draft'),
        ),
      ]);
      expect(results.map((record) => record.requestId), everyElement(request));
      expect(
        results.map((record) => record.note),
        everyElement('Original evidence'),
      );
      expect((await read(second))!.requestId, request);
    },
  );

  test('separate intents survive without overwriting the owner map', () async {
    final storage = MemoryStorage();
    final store = PaymentHelpPendingStore(storage: storage)..bindOwner(owner);
    await store.retain(checkpoint());
    await store.retain(
      checkpoint(intentId: secondIntent, requestId: nextRequest),
    );
    expect((await read(store))!.requestId, request);
    expect((await read(store, intentId: secondIntent))!.requestId, nextRequest);
  });

  test(
    'owner change during write fences completion and removes original bytes',
    () async {
      final storage = MemoryStorage()
        ..writing = Completer<void>()
        ..release = Completer<void>();
      final store = PaymentHelpPendingStore(storage: storage)..bindOwner(owner);
      final saving = store.retain(checkpoint());
      final assertion = expectLater(saving, throwsStateError);
      await storage.writing!.future;
      store.bindOwner(other);
      storage.release!.complete();
      await assertion;
      await store.ensureCleanup();
      expect(storage.values, isEmpty);
      expect(
        await store.read(ownerId: other, collectionId: group, intentId: intent),
        isNull,
      );
    },
  );

  test(
    'logout clears only original owner and cleanup failure remains retryable',
    () async {
      final storage = MemoryStorage();
      final store = PaymentHelpPendingStore(storage: storage)..bindOwner(owner);
      await store.retain(checkpoint());
      storage.values[other] = 'independent owner ciphertext placeholder';
      storage.failClear = true;
      store.bindOwner(null);
      await expectLater(store.ensureCleanup(), throwsStateError);
      expect(storage.values[owner], isNotNull);
      storage.failClear = false;
      await store.ensureCleanup();
      expect(storage.values.containsKey(owner), isFalse);
      expect(storage.values[other], isNotNull);
    },
  );

  test(
    'same owner rebind preserves pending request across replacement session',
    () async {
      final storage = MemoryStorage();
      final store = PaymentHelpPendingStore(storage: storage)..bindOwner(owner);
      await store.retain(checkpoint());
      store.bindOwner(owner);
      expect((await read(store))!.requestId, request);
    },
  );

  test(
    'corrupt or foreign bytes block new commands without replacing evidence',
    () async {
      for (final raw in [
        'not-json',
        '{"version":1,"owner_id":"$other","requests":[]}',
        'x' * (PaymentHelpPendingStore.maximumBytes + 1),
      ]) {
        final storage = MemoryStorage()..values[owner] = raw;
        final store = PaymentHelpPendingStore(storage: storage)
          ..bindOwner(owner);
        await expectLater(store.retain(checkpoint()), throwsFormatException);
        expect(storage.values[owner], raw);
      }
    },
  );

  test('failed durable write exposes no successful claim', () async {
    final storage = MemoryStorage()..failWrite = true;
    final store = PaymentHelpPendingStore(storage: storage)..bindOwner(owner);
    await expectLater(store.retain(checkpoint()), throwsStateError);
    expect(storage.values, isEmpty);
    storage.failWrite = false;
    expect((await store.retain(checkpoint())).requestId, request);
  });

  test('receipt can acknowledge only the exact original command', () async {
    final storage = MemoryStorage();
    final store = PaymentHelpPendingStore(storage: storage)..bindOwner(owner);
    await store.retain(checkpoint());
    await expectLater(
      store.acknowledge(checkpoint(note: 'Altered evidence')),
      throwsFormatException,
    );
    expect((await read(store))!.received, isFalse);
  });

  test(
    'native adapter uses isolated channel and requires committed write ack',
    () async {
      const channel = MethodChannel('collect/payment_help_pending');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return call.method == 'read' ? null : false;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final store = PaymentHelpPendingStore()..bindOwner(owner);
      await expectLater(store.retain(checkpoint()), throwsStateError);
      expect(calls.map((call) => call.method), ['read', 'write']);
      expect((calls.last.arguments as Map)['owner_id'], owner);
      final saved =
          jsonDecode((calls.last.arguments as Map)['value'] as String) as Map;
      expect(saved['requests'], hasLength(1));
    },
  );
}
