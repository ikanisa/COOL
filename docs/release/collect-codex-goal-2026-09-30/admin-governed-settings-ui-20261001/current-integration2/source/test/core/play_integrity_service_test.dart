import 'package:collect_app/core/security/play_integrity_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SMS integrity hash binds the exact provider envelope', () {
    const service = PlayIntegrityService();
    const common = (
      subjectId: '97000000-0000-4000-8000-000000000001',
      nonce: '97000000-0000-4000-8000-000000000099',
      receiverHash:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      envelopeId: '97000000-0000-4000-8000-000000000111',
      sender: 'M-Money',
      body: 'You have received RWF 1,234. Transaction ID ABC12345',
      receivedAt: '2026-09-03T10:00:00.000Z',
    );

    String hash({String? body, String? sender, String? envelope}) =>
        service.buildSmsIngestionRequestHash(
          subjectId: common.subjectId,
          nonce: common.nonce,
          receiverMomoNumberHash: common.receiverHash,
          clientEnvelopeId: envelope ?? common.envelopeId,
          rawSender: sender ?? common.sender,
          rawBody: body ?? common.body,
          receivedAtDevice: common.receivedAt,
        );

    expect(
      hash(),
      '16f277bbeb637cf8bb8da6a4a90e98451232d996278497444437329fa3c1b26b',
    );
    expect(hash(body: '${common.body}.'), isNot(hash()));
    expect(hash(sender: 'Unknown'), isNot(hash()));
    expect(
      hash(envelope: '97000000-0000-4000-8000-000000000112'),
      isNot(hash()),
    );
  });
}
