import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:collect_app/admin/core/admin_receipt_aggregate_v2_models.dart';
import 'package:collect_app/admin/core/admin_receipt_aggregate_v2_sdk.dart';

// The fixture root is an explicit test argument in an isolated overlay. The
// promoted canonical suite defaults to its canonical fixture membership.
const fixtureRoot = String.fromEnvironment(
  'COLLECT_AGGREGATE_FIXTURE_ROOT',
  defaultValue: 'test/fixtures/receipt_aggregate_v2',
);
Map<String, dynamic> read(String name) =>
    jsonDecode(File('$fixtureRoot/$name.json').readAsStringSync())
        as Map<String, dynamic>;
Map<String, dynamic> copy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
Map<String, dynamic> envelope(Map<String, dynamic> result) => {
  'contract_version': 2,
  'request_id': result['request_id'],
  'status': 'available',
  'result': result,
  'financial_action': false,
  'send_action': false,
};
void main() {
  final original = read('actual-worker-v2');
  final request = original['request_id'] as String;
  Map<String, dynamic> initial() => copy(original);
  test(
    'actual two-family worker side validates independently of legacy v1 status',
    () {
      final v = AdminReceiptAggregateSampleV2.parse(
        envelope(initial()),
        request,
      );
      expect(v.available, isTrue);
      expect(v.measurement!.admitted, isTrue);
      expect(v.measurement!.metrics.callbacks!['armed_attempts_24h'], 2);
    },
  );
  test('original job expiry bounds currentness even inside sample window', () {
    final r = initial();
    final at = DateTime.parse(r['recorded_at'] as String);
    r['expires_at'] = at.add(const Duration(seconds: 20)).toIso8601String();
    final v = AdminReceiptAggregateSampleV2.parse(envelope(r), request);
    expect(v.configurationRevision, r['configuration_revision']);
    expect(v.telemetryRevision, r['telemetry_revision']);
    expect(v.policyRevision, r['policy_revision']);
    expect(v.current(at.add(const Duration(seconds: 19))), isTrue);
    expect(v.current(at.add(const Duration(seconds: 20))), isFalse);
    expect(v.current(at.subtract(const Duration(microseconds: 1))), isFalse);
  });
  test('actual consistent coverage stays a framework observation', () {
    final r = read('actual-worker-covered-v2');
    final v = AdminReceiptAggregateSampleV2.parse(
      envelope(r),
      r['request_id'] as String,
    );
    expect(
      v.measurement!.metrics.callbacks!['complete_delivery_callback_attempts'],
      2,
    );
  });
  test('actual conflicts remain uncertain in both protocols', () {
    final r = read('actual-worker-conflict-v2');
    final v = AdminReceiptAggregateSampleV2.parse(
      envelope(r),
      r['request_id'] as String,
    );
    expect(v.measurement!.metrics.unknown!['uncertain_attempts'], 2);
  });
  test('inactive and missing samples never become healthy zero', () {
    final v = AdminReceiptAggregateV2.parse(read('inactive-v2'));
    expect(v.admitted, isFalse);
    expect(v.metrics.callbacks, isNull);
    final missing = AdminReceiptAggregateSampleV2.parse({
      'contract_version': 2,
      'request_id': request,
      'status': 'unavailable',
      'result': null,
      'financial_action': false,
      'send_action': false,
    }, request);
    expect(missing.available, isFalse);
    expect(missing.current(DateTime.now()), isFalse);
  });
  test('immutable expired sample stays readable and explicitly stale', () {
    final v = AdminReceiptAggregateSampleV2.parse(envelope(initial()), request);
    expect(v.available, isTrue);
    expect(v.current(v.recordedAt!.add(const Duration(minutes: 2))), isFalse);
    expect(v.current(v.recordedAt!), isTrue);
  });
  for (final key in [
    'financial_action',
    'send_action',
    'carrier_proof',
    'delivery_proven',
  ]) {
    test('refuses $key authority inflation', () {
      final r = initial();
      (r['measurement'] as Map)[key] = true;
      expect(
        () => AdminReceiptAggregateSampleV2.parse(envelope(r), request),
        throwsFormatException,
      );
    });
  }
  test(
    'unknown key, partial metrics, v1 identity and family aliases refuse',
    () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (m) => m['unknown_field'] = 0,
        (m) => m['callbacks'] = null,
        (m) => m['contract_version'] = 1,
        (m) => m['protocol_families'] = ['primary_v2', 'receipt_successor'],
      ]) {
        final r = initial();
        mutate(r['measurement'] as Map<String, dynamic>);
        expect(
          () => AdminReceiptAggregateSampleV2.parse(envelope(r), request),
          throwsFormatException,
        );
      }
    },
  );
  test('admitted count above every exact completeness ceiling refuses', () {
    for (final entry in AdminReceiptAggregateV2.ceilings.entries) {
      final r = initial();
      final m = r['measurement'] as Map;
      (m['probe_counts'] as Map)[entry.key] = entry.value + 1;
      expect(
        () => AdminReceiptAggregateSampleV2.parse(envelope(r), request),
        throwsFormatException,
        reason: entry.key,
      );
    }
  });
  test(
    'mismatched original request, final policy and partial projection refuse',
    () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (r) => r['request_id'] = '00000000-0000-4000-8000-000000000001',
        (r) => r['policy_revision'] = (r['policy_revision'] as int) + 1,
        (r) => (r['projection'] as Map)['complete'] = false,
        (r) => (r['projection'] as Map)['processed'] = 26,
      ]) {
        final r = initial();
        mutate(r);
        expect(
          () => AdminReceiptAggregateSampleV2.parse(envelope(r), request),
          throwsFormatException,
        );
      }
    },
  );
  test('fractional, oversized and inconsistent measurements refuse', () {
    for (final value in [2.0, 1000000001, -1]) {
      final r = initial();
      ((r['measurement'] as Map)['callbacks'] as Map)['expected_segments'] =
          value;
      expect(
        () => AdminReceiptAggregateSampleV2.parse(envelope(r), request),
        throwsFormatException,
      );
    }
    final r = initial();
    ((r['measurement'] as Map)['backlog'] as Map)['unhandled_events'] = 8;
    expect(
      () => AdminReceiptAggregateSampleV2.parse(envelope(r), request),
      throwsFormatException,
    );
  });
  test('SDK is a one-tool read with a closed identifier parameter', () async {
    final calls = <List<Object?>>[];
    final api = AdminReceiptAggregateV2Api(
      isCurrent: () => true,
      rpc: (name, p) async {
        calls.add([name, p]);
        return envelope(initial());
      },
    );
    expect((await api.sample(request)).available, isTrue);
    expect(calls, [
      [
        'admin_get_receipt_aggregate_sample_v2',
        {'p_request_id': request},
      ],
    ]);
  });
  test('SDK refuses missing session before issuing any request', () async {
    var calls = 0;
    final api = AdminReceiptAggregateV2Api(
      isCurrent: () => false,
      rpc: (_, _) async {
        calls++;
        return envelope(initial());
      },
    );
    await expectLater(
      api.sample(request),
      throwsA(isA<ReceiptAggregateV2SessionChanged>()),
    );
    expect(calls, 0);
  });
  test('SDK discards late response after session revocation', () async {
    var current = true;
    final completer = Completer<Object?>();
    final api = AdminReceiptAggregateV2Api(
      isCurrent: () => current,
      rpc: (_, _) => completer.future,
    );
    final pending = api.sample(request);
    final expectation = expectLater(
      pending,
      throwsA(isA<ReceiptAggregateV2SessionChanged>()),
    );
    current = false;
    completer.complete(envelope(initial()));
    await expectation;
  });
  test(
    'SDK preserves RPC denial without fabricating an unavailable sample',
    () async {
      final error = StateError('Denied synthetic RPC');
      final api = AdminReceiptAggregateV2Api(
        isCurrent: () => true,
        rpc: (_, _) async => throw error,
      );
      await expectLater(api.sample(request), throwsA(same(error)));
    },
  );
  testWidgets('SDK timeout does not fabricate a sample', (tester) async {
    final api = AdminReceiptAggregateV2Api(
      isCurrent: () => true,
      rpc: (_, _) => Completer<Object?>().future,
    );
    final expectation = expectLater(
      api.sample(request),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump(const Duration(seconds: 16));
    await expectation;
  });
}
