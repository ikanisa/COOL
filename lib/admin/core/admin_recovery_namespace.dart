/// An earlier storage generation still owns a browser original. It is never
/// imported, rebound, resolved or replayed by the current generation.
class AdminEarlierRecoveryPending extends FormatException {
  const AdminEarlierRecoveryPending()
    : super(
        'An earlier saved operation requires separate review. Its browser record has been preserved.',
      );
}

/// Enumerate keys only: saved original values and other current owners stay
/// untouched. An incomplete or changing storage index refuses admission.
void verifyAdminRecoveryNamespace({
  required String retiredPrefix,
  required int Function() storageLength,
  required String? Function(int) keyAt,
}) {
  final count = storageLength();
  if (count < 0 || count > 10000) {
    throw const FormatException('Recovery storage could not be checked.');
  }
  final keys = <String>[];
  for (var index = 0; index < count; index++) {
    final key = keyAt(index);
    if (key == null) {
      throw const FormatException('Recovery storage changed during review.');
    }
    if (key.startsWith(retiredPrefix)) {
      throw const AdminEarlierRecoveryPending();
    }
    keys.add(key);
  }
  if (storageLength() != count) {
    throw const FormatException('Recovery storage changed during review.');
  }
  // A same-size replacement or reordering must not turn an incomplete scan
  // into apparent absence. Two bounded passes keep this check linear.
  for (var index = 0; index < count; index++) {
    if (keyAt(index) != keys[index]) {
      throw const FormatException('Recovery storage changed during review.');
    }
  }
  if (storageLength() != count) {
    throw const FormatException('Recovery storage changed during review.');
  }
}
