import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'admin_runtime.dart';
import 'admin_receipt_notice_content_host.dart';
import 'admin_receipt_notice_content_models.dart';
import 'admin_receipt_notice_dispatch_models.dart';
import 'admin_receipt_notice_dispatch_sdk.dart';
import 'admin_receipt_notice_dispatch_checkpoint.dart';
import 'admin_receipt_notice_dispatch_controller.dart';
import 'admin_receipt_notice_dispatch_view.dart';

class AdminReceiptNoticeDispatchAccess {
  const AdminReceiptNoticeDispatchAccess({
    required this.api,
    required this.actorId,
    required this.sessionId,
    required this.isCurrent,
    required this.canManage,
    required this.store,
  });
  final AdminReceiptNoticeDispatchApi api;
  final String actorId, sessionId;
  final bool Function() isCurrent, canManage;
  final AdminReceiptNoticeDispatchStore? store;
  Future<AdminReceiptNoticePreparedReference> preservePrepared({
    required AdminReceiptNoticeInspection inspection,
    required AdminReceiptNoticeRequest recorded,
    required AdminReceiptNoticeIntent original,
  }) async {
    final target = store;
    if (target == null || !isCurrent()) noticeInvalid();
    final reference = AdminReceiptNoticePreparedReference.fromRecorded(
      inspection: inspection,
      recorded: recorded,
      original: original,
      actorId: actorId,
      sessionId: sessionId,
    );
    await preserveReceiptNoticePreparedHandoff(
      reference: reference,
      store: target,
      isCurrent: isCurrent,
    );
    return reference;
  }
}

final adminReceiptNoticeDispatchStoreProvider =
    Provider<AdminReceiptNoticeDispatchStore?>(
      (ref) => browserReceiptNoticeDispatchStore(),
    );
final adminReceiptNoticeDispatchAccessProvider =
    Provider.autoDispose<AdminReceiptNoticeDispatchAccess?>((ref) {
      final original = ref.watch(adminReceiptNoticeContentAccessProvider);
      if (original == null) return null;
      final now = ref.watch(adminClockProvider),
          store = ref.watch(adminReceiptNoticeDispatchStoreProvider);
      final api = AdminReceiptNoticeDispatchSdk(
        rpc: (name, parameters) => original.repository.rpcMap(
          name,
          params: parameters,
          automaticRetry: false,
        ),
        actorId: original.actorId,
        sessionId: original.sessionId,
        isCurrent: original.isCurrent,
        canManage: original.canManage,
        now: now,
      );
      return AdminReceiptNoticeDispatchAccess(
        api: api,
        actorId: original.actorId,
        sessionId: original.sessionId,
        isCurrent: original.isCurrent,
        canManage: original.canManage,
        store: store,
      );
    });

class AdminReceiptNoticeDispatchConfigurationHost extends ConsumerWidget {
  const AdminReceiptNoticeDispatchConfigurationHost({
    this.onRecorded,
    super.key,
  });
  final VoidCallback? onRecorded;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(adminReceiptNoticeDispatchAccessProvider),
        identity = ref.watch(adminIdentityProvider).asData?.value;
    if (access == null ||
        identity?.permissions.contains('settings.read') != true) {
      return const _Unavailable();
    }
    return _ControllerHost(
      access: access,
      onRecorded: onRecorded,
      key: ValueKey('configuration.${access.actorId}.${access.sessionId}'),
    );
  }
}

class AdminReceiptNoticeDispatchHost extends ConsumerWidget {
  const AdminReceiptNoticeDispatchHost({
    required this.reference,
    this.onRecorded,
    super.key,
  });
  final AdminReceiptNoticePreparedReference reference;
  final VoidCallback? onRecorded;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(adminReceiptNoticeDispatchAccessProvider);
    if (access == null ||
        reference.actorId != access.actorId ||
        reference.sessionId != access.sessionId) {
      return const _Unavailable();
    }
    return _ControllerHost(
      access: access,
      reference: reference,
      onRecorded: onRecorded,
      key: ValueKey(
        '${access.actorId}.${access.sessionId}.${reference.fingerprint}',
      ),
    );
  }
}

/// Mounted only against the parent's fresh, strictly joined financial identifiers.
/// Restored local metadata is not current authority; each child fresh-inspects1700.
class AdminReceiptNoticeDispatchSourceHost extends ConsumerStatefulWidget {
  const AdminReceiptNoticeDispatchSourceHost({
    required this.outboxId,
    required this.sourceSnapshotId,
    required this.collectionId,
    this.reversalSnapshotId,
    this.onRecorded,
    super.key,
  });
  final String outboxId, sourceSnapshotId, collectionId;
  final String? reversalSnapshotId;
  final VoidCallback? onRecorded;
  @override
  ConsumerState<AdminReceiptNoticeDispatchSourceHost> createState() =>
      _SourceHostState();
}

class _SourceHostState
    extends ConsumerState<AdminReceiptNoticeDispatchSourceHost> {
  AdminReceiptNoticeDispatchAccess? _access;
  Future<List<AdminReceiptNoticePreparedReference>>? _future;
  String? _binding;
  Future<List<AdminReceiptNoticePreparedReference>> _read(
    AdminReceiptNoticeDispatchAccess access,
  ) async {
    final store = access.store;
    if (store == null || !access.isCurrent()) noticeInvalid();
    final found = <AdminReceiptNoticePreparedReference>[];
    for (final pair in [
      (AdminReceiptNoticeFamily.duplicateCopy, widget.sourceSnapshotId),
      if (widget.reversalSnapshotId != null)
        (AdminReceiptNoticeFamily.reversalNotice, widget.reversalSnapshotId!),
    ]) {
      final reference = await store.latestPrepared(
        access.actorId,
        access.sessionId,
        widget.outboxId,
        pair.$2,
        widget.collectionId,
        pair.$1,
      );
      if (!access.isCurrent()) noticeInvalid();
      if (reference != null) found.add(reference);
    }
    return found;
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(adminReceiptNoticeDispatchAccessProvider),
        binding =
            '${widget.outboxId}.${widget.sourceSnapshotId}.${widget.collectionId}.${widget.reversalSnapshotId}';
    if (access == null) return const _Unavailable();
    if (!identical(access, _access) || binding != _binding) {
      _access = access;
      _binding = binding;
      _future = _read(access);
    }
    return FutureBuilder<List<AdminReceiptNoticePreparedReference>>(
      future: _future,
      builder: (context, snapshot) {
        if (!access.isCurrent()) return const _Unavailable();
        if (snapshot.connectionState != ConnectionState.done) {
          return const LinearProgressIndicator(
            semanticsLabel: 'Restoring prepared notice references',
          );
        }
        if (snapshot.hasError) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Durable prepared notice references are unavailable. Restore browser storage or recover the original content request before continuing.',
              ),
            ),
          );
        }
        final references = snapshot.data ?? [];
        if (references.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Prepare immutable notice content to review dispatch approval. No prepared review is inferred from the original receipt.',
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final reference in references)
              AdminReceiptNoticeDispatchHost(
                reference: reference,
                onRecorded: widget.onRecorded,
              ),
          ],
        );
      },
    );
  }
}

class _ControllerHost extends ConsumerStatefulWidget {
  const _ControllerHost({
    required this.access,
    this.reference,
    this.onRecorded,
    super.key,
  });
  final AdminReceiptNoticeDispatchAccess access;
  final AdminReceiptNoticePreparedReference? reference;
  final VoidCallback? onRecorded;
  @override
  ConsumerState<_ControllerHost> createState() => _ControllerHostState();
}

class _ControllerHostState extends ConsumerState<_ControllerHost> {
  late AdminReceiptNoticeDispatchController _controller;
  void _create() {
    final access = widget.access;
    _controller = AdminReceiptNoticeDispatchController(
      api: access.api,
      actorId: access.actorId,
      sessionId: access.sessionId,
      isCurrent: access.isCurrent,
      canManage: access.canManage,
      now: ref.read(adminClockProvider),
      newRequestId: const Uuid().v4,
      store: access.store,
      reference: widget.reference,
      onRecorded: widget.onRecorded,
    );
  }

  @override
  void initState() {
    super.initState();
    _create();
  }

  @override
  void didUpdateWidget(_ControllerHost old) {
    super.didUpdateWidget(old);
    if (!identical(old.access, widget.access) ||
        old.reference?.fingerprint != widget.reference?.fingerprint) {
      _controller.dispose();
      _create();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      AdminReceiptNoticeDispatchView(controller: _controller);
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();
  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(20),
      child: Text(
        'Current email-owner permission is required to review notice dispatch.',
      ),
    ),
  );
}
