import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:collect_app/core/security/durable_sms_receipt.dart';
import 'package:collect_app/core/security/sms_access_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = '11111111-1111-4111-8111-111111111111';
  const envelope = '22222222-2222-4222-8222-222222222222';
  const raw = '44444444-4444-4444-8444-444444444444';
  const body = ' receipt body é ';
  Map<String, Object?> payload() => {
    'ok': true,
    'receipt': {
      'contract_version': 2,
      'stored': true,
      'raw_sms_id': raw,
      'owner_user_id': owner,
      'client_envelope_id': envelope,
      'body_sha256': sha256.convert(utf8.encode(body)).toString(),
    },
  };
  DurableSmsReceipt decode(Object? value) => DurableSmsReceipt.decode(
    value,
    expectedOwner: owner,
    expectedEnvelope: envelope,
    rawBody: body,
  );
  test('valid ACK retains exact envelope owner and digest', () {
    final result = decode(payload());
    expect(result.ownerUserId, owner);
    expect(result.envelopeId, envelope);
    expect(result.rawSmsId, raw);
  });
  test('JSON transport decoding remains supported', () {
    expect(decode(jsonEncode(payload())).ownerUserId, owner);
  });
  for (final entry in <String, Object?>{
    'stored': false,
    'contract_version': 1,
    'owner_user_id': raw,
    'client_envelope_id': raw,
    'raw_sms_id': 'invalid',
    'body_sha256': 'wrong',
  }.entries) {
    test('rejects contradictory ${entry.key}', () {
      final value = payload();
      (value['receipt'] as Map)[entry.key] = entry.value;
      expect(() => decode(value), throwsFormatException);
    });
  }
  for (final value in [
    null,
    [],
    {},
    {'ok': true},
    'not-json',
  ]) {
    test('rejects missing ACK ${value.runtimeType}', () {
      expect(() => decode(value), throwsFormatException);
    });
  }
  const channel = MethodChannel('collect/sms_access');
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test('bridge sends native owner and exact body proof', () async {
    final receipt = decode(payload());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'ackPendingSms');
          final args = call.arguments as Map;
          expect(args['owner_user_id'], owner);
          expect(args['contract_version'], 2);
          expect(args['ids'], [envelope]);
          expect((args['body_hashes'] as Map)[envelope], receipt.bodySha256);
          return true;
        });
    expect(
      await const SmsAccessChannel().acknowledgeDurableReceipt(receipt),
      isTrue,
    );
  });
  test('native error never becomes successful ACK', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: 'locked'),
        );
    expect(
      await const SmsAccessChannel().acknowledgeDurableReceipt(
        decode(payload()),
      ),
      isFalse,
    );
  });
  test('null queue is not an empty successful read', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect((call.arguments as Map)['owner_user_id'], owner);
          return null;
        });
    await expectLater(
      const SmsAccessChannel().readPendingSms(ownerUserId: owner),
      throwsStateError,
    );
  });
  test('queue read requires an authenticated account', () async {
    await expectLater(
      const SmsAccessChannel().readPendingSms(ownerUserId: ''),
      throwsStateError,
    );
  });
  test('bridge rejects another account in a native queue read', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'readPendingSms');
          expect((call.arguments as Map)['owner_user_id'], owner);
          return [
            {
              'id': envelope,
              'owner_user_id': raw,
              'raw_sender': 'M-Money',
              'raw_body': body,
              'received_at_device': '2026-09-28T10:00:00Z',
            },
          ];
        });
    await expectLater(
      const SmsAccessChannel().readPendingSms(ownerUserId: owner),
      throwsFormatException,
    );
  });
  test('legacy acknowledgement cannot delete nonempty receipts', () async {
    expect(
      await const SmsAccessChannel().acknowledgePendingSms([envelope]),
      isFalse,
    );
  });
  test('queue health flag is decoded without inventing a healthy status', () {
    expect(
      SmsAccessStatus.fromMap({'queue_unavailable': true}).queueUnavailable,
      isTrue,
    );
  });
}
