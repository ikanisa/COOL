@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_read_contracts.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const packetPath = String.fromEnvironment('SELFHOST_ADMIN_OVERVIEW_PACKET');
const packetSha = String.fromEnvironment('SELFHOST_ADMIN_OVERVIEW_SHA256');

void main() {
  test('current synthetic SQL overview reaches the strict Admin decoder', () {
    expect(packetPath, isNotEmpty);
    final bytes = File(packetPath).readAsBytesSync();
    expect(sha256.convert(bytes).toString(), packetSha);
    final packet = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(packet['format'], 'collect.selfhost.admin-overview.synthetic.v1');
    expect(packet['provider_calls'], 0);
    expect(packet['synthetic_actor_permissions'], true);
    expect(packet['hosted_acceptance'], false);
    final source = packet['source'] as Map<String, dynamic>;
    final history = source['history'] as Map<String, dynamic>;
    for (final file in [
      ...history['files'] as List<dynamic>,
      ...source['extra'] as List<dynamic>,
    ]) {
      final record = file as Map<String, dynamic>;
      final body = File(record['role'] as String).readAsBytesSync();
      expect(body.length, record['bytes']);
      expect(sha256.convert(body).toString(), record['sha256']);
    }
    final overview = parseAdminOverview(
      Map<String, dynamic>.from(packet['overview'] as Map),
    );
    final limited = parseAdminOverview(
      Map<String, dynamic>.from(packet['limited'] as Map),
    );
    expect(overview, hasLength(3));
    expect(limited, hasLength(1));
    expect(packet['denied'], true);
    expect(packet['statements'], isNotEmpty);
  });
}
