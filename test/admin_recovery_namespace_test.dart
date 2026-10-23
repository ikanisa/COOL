import 'package:collect_app/admin/core/admin_recovery_namespace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const retired = 'collect.admin.example.recovery.v1.';
  const current = 'collect.admin.example.recovery.v2.';
  void verify(Map<String, String> storage) => verifyAdminRecoveryNamespace(
    retiredPrefix: retired,
    storageLength: () => storage.length,
    keyAt: (index) => storage.keys.elementAt(index),
  );

  test('empty current storage and another current owner remain separate', () {
    verify({});
    verify({
      'theme': 'dark',
      '${current}another-owner': 'unread private bytes',
    });
  });
  for (final suffix in ['retained-original', 'retained-original.resolution']) {
    test('earlier $suffix refuses admission without changing saved bytes', () {
      final storage = {'$retired$suffix': 'exact earlier opaque bytes'};
      final before = Map<String, String>.from(storage);
      expect(
        () => verify(storage),
        throwsA(isA<AdminEarlierRecoveryPending>()),
      );
      expect(storage, before);
    });
  }
  test('an incomplete or changed storage index cannot establish absence', () {
    expect(
      () => verifyAdminRecoveryNamespace(
        retiredPrefix: retired,
        storageLength: () => 1,
        keyAt: (_) => null,
      ),
      throwsFormatException,
    );
    var reads = 0;
    expect(
      () => verifyAdminRecoveryNamespace(
        retiredPrefix: retired,
        storageLength: () => ++reads,
        keyAt: (_) => '${current}another-owner',
      ),
      throwsFormatException,
    );
  });
  for (final mutation in ['replacement', 'reordering']) {
    test('same-count key $mutation cannot establish absence', () {
      final first = ['${current}first-owner', '${current}second-owner'];
      final changed = mutation == 'replacement'
          ? ['${current}first-owner', '${retired}new-pending-original']
          : first.reversed.toList();
      var keyReads = 0;
      expect(
        () => verifyAdminRecoveryNamespace(
          retiredPrefix: retired,
          storageLength: () => first.length,
          keyAt: (index) =>
              (++keyReads <= first.length ? first : changed)[index],
        ),
        throwsFormatException,
      );
      expect(keyReads, greaterThan(first.length));
    });
  }
  test('oversized storage cannot bypass the bounded admission check', () {
    expect(
      () => verifyAdminRecoveryNamespace(
        retiredPrefix: retired,
        storageLength: () => 10001,
        keyAt: (_) => throw StateError('must not enumerate'),
      ),
      throwsFormatException,
    );
  });
}
