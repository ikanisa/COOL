import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_investigation.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> observed() =>
    jsonDecode(
          File(
            'contracts/collect-receipt-content-v2/observed-investigation-v2.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

void main() {
  test('actual isolated v2 receipt read preserves safe dated preview', () {
    final raw = observed();
    final snapshot = AdminInvestigationSnapshot.parse(raw);
    final receipt = snapshot.receipt!;
    expect(receipt.templateVersion, 2);
    expect(receipt.maskedSnapshotPreview, contains('bwanditswe'));
    expect(receipt.maskedSnapshotPreview, contains('CAT:'));
    expect(receipt.maskedSnapshotPreview, isNot(contains('Balance y')));
    expect(receipt.maskedSnapshotPreview, isNot(contains('POLICY-1')));
    expect(receipt.memberRwf, '950');
    expect(snapshot.payment!.journals.single.snapshot!.memberRwf, '950');
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
      final raw = observed();
      (raw['receipt'] as Map<String, dynamic>)['template_version'] =
          unsupported;
      expect(
        () => AdminInvestigationSnapshot.parse(raw),
        throwsFormatException,
      );
    });
  }
}
