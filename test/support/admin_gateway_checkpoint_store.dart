import 'package:collect_app/admin/core/admin_gateway_checkpoint.dart';

class MemoryAdminGatewayCheckpointStore implements AdminGatewayCheckpointStore {
  final values = <String, String>{};
  bool failRead = false, failWrite = false, failClear = false;
  bool corruptReadback = false, ignoreClear = false;
  int writes = 0;
  @override
  String? read(String ownerDigest) {
    if (failRead) throw StateError('PRIVATE_STORAGE_CANARY');
    if (corruptReadback && values.containsKey(ownerDigest)) return '{}';
    return values[ownerDigest];
  }

  @override
  void write(String ownerDigest, String encoded) {
    writes++;
    if (failWrite) throw StateError('PRIVATE_STORAGE_CANARY');
    values[ownerDigest] = encoded;
  }

  @override
  void clear(String ownerDigest) {
    if (failClear) throw StateError('PRIVATE_STORAGE_CANARY');
    if (!ignoreClear) values.remove(ownerDigest);
  }
}
