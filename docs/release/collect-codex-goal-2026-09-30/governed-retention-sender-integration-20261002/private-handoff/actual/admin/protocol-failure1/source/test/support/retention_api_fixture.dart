import 'dart:async';
import 'package:collect_app/admin/core/admin_sender_retention_models.dart';
import 'package:collect_app/admin/core/admin_sender_retention_sdk.dart';
import 'package:collect_app/admin/core/admin_sender_retention_controller.dart';
import 'package:collect_app/admin/core/admin_sender_retention_checkpoint.dart';
import 'retention_fixture.dart';

class Store implements AdminRetentionStore {
  AdminRetentionIntent? value;
  bool failWrite = false;
  int writes = 0, clears = 0;
  @override
  Future<AdminRetentionIntent?> read(String a, String s) async => value;
  @override
  Future<void> write(AdminRetentionIntent i) async {
    writes++;
    if (failWrite) throw StateError('storage blocked');
    value = i;
  }

  @override
  Future<void> clear(AdminRetentionIntent i) async {
    if (value?.fingerprint != i.fingerprint) throw StateError('conflict');
    clears++;
    value = null;
  }
}

class Api implements AdminRetentionApi {
  int changes = 0, lookups = 0;
  Object? readError, changeError, lookupError;
  Completer<AdminRetentionRequest>? wait;
  AdminRetentionSnapshot snapshot = initial();
  AdminRetentionRequest? lookup;
  @override
  Future<AdminRetentionSnapshot> read() async {
    if (readError != null) throw readError!;
    return snapshot;
  }

  @override
  Future<AdminRetentionRequest> configure(AdminRetentionIntent i) async {
    changes++;
    if (changeError != null) throw changeError!;
    if (wait != null) return wait!.future;
    return recorded();
  }

  @override
  Future<AdminRetentionRequest> recover(AdminRetentionIntent i) async {
    lookups++;
    if (lookupError != null) throw lookupError!;
    return lookup ?? recorded();
  }
}

AdminRetentionController control(
  Api api,
  Store? store, {
  bool Function()? current,
  DateTime Function()? clock,
}) => AdminRetentionController(
  api: api,
  actorId: actor,
  sessionId: session,
  store: store,
  now: clock ?? () => fixtureNow,
  isCurrent: current ?? () => true,
  newRequestId: () => originalIntent().requestId,
);
Future<void> apply(AdminRetentionController c) => c.apply(
  enabled: false,
  batchLimit: 12,
  byteLimit: 1048576,
  reason: 'Synthetic governed maintenance test',
);
