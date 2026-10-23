import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_investigation.dart';
import 'package:flutter_test/flutter_test.dart';

// Declared version-2 parser example built from the existing synthetic version-1 DTO.
Map<String, dynamic> contentFixture() {
  final raw =
      jsonDecode(
            File(
              'test/fixtures/admin_investigation_v1.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final receipt = raw['receipt'] as Map<String, dynamic>;
  receipt['template_version'] = 2;
  receipt['masked_snapshot_preview'] =
      'Ubwizigame bwa 1,200 RWF bwanditswe. Igiteranyo cyanditswe ku 2026-09-30 21:00 CAT: 6,700 RWF. Ref: snapshot-77777777.';
  return raw;
}

void main() {
  test('synthetic v2 receipt preserves safe dated preview', () {
    final raw = contentFixture();
    final snapshot = AdminInvestigationSnapshot.parse(raw);
    final receipt = snapshot.receipt!;
    expect(receipt.templateVersion, 2);
    expect(receipt.maskedSnapshotPreview, contains('bwanditswe'));
    expect(receipt.maskedSnapshotPreview, contains('CAT:'));
    expect(receipt.maskedSnapshotPreview, isNot(contains('Balance y')));
    expect(receipt.maskedSnapshotPreview, isNot(contains('POLICY-1')));
    expect(receipt.memberRwf, '6700');
    expect(snapshot.payment!.journals.single.snapshot!.memberRwf, '6700');
  });

  test('legacy v1 remains readable as retained historic evidence', () {
    final raw =
        jsonDecode(
              File(
                'test/fixtures/admin_investigation_v1.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(AdminInvestigationSnapshot.parse(raw).receipt!.templateVersion, 1);
  });

  for (final unsupported in [0, 3, 2.0, '2', null]) {
    test('unsupported content version $unsupported remains fail closed', () {
      final raw = contentFixture();
      (raw['receipt'] as Map<String, dynamic>)['template_version'] =
          unsupported;
      expect(
        () => AdminInvestigationSnapshot.parse(raw),
        throwsFormatException,
      );
    });
  }
}
