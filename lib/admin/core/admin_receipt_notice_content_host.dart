import '../shared/components/admin_data_listing.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'admin_auth_guard.dart';
import 'admin_runtime.dart';
import 'admin_models.dart';
import 'admin_receipt_notice_content_models.dart';
import 'admin_receipt_notice_content_sdk.dart';
import 'admin_receipt_notice_content_checkpoint.dart';
import 'admin_receipt_notice_content_controller.dart';
import 'admin_receipt_notice_content_view.dart';
import 'admin_receipt_notice_dispatch_host.dart';

class AdminReceiptNoticeContentAccess {
  const AdminReceiptNoticeContentAccess({
    required this.api,
    required this.repository,
    required this.actorId,
    required this.sessionId,
    required this.isCurrent,
    required this.canManage,
    required this.canListGroups,
  });
  final AdminReceiptNoticeContentApi api;
  final AdminRepository repository;
  final String actorId, sessionId;
  final bool Function() isCurrent, canManage, canListGroups;
}

final adminReceiptNoticeContentStoreProvider =
    Provider<AdminReceiptNoticeContentStore?>(
      (ref) => browserReceiptNoticeContentStore(),
    );
final adminReceiptNoticeContentAccessProvider =
    Provider.autoDispose<AdminReceiptNoticeContentAccess?>((ref) {
      final scope = ref.watch(adminAuthSessionScopeProvider),
          repository = ref.watch(adminRepositoryProvider),
          state = ref.watch(adminIdentityProvider);
      final identity = state.isLoading || state.hasError
          ? null
          : state.asData?.value;
      if (scope == null ||
          identity == null ||
          identity.userId != scope.key.userId ||
          !identity.roles.contains('platform_owner') ||
          !{
            'payments.read',
            'notifications.read',
            'system_health.read',
          }.every(identity.permissions.contains) ||
          repository is! AdminRepository) {
        return null;
      }
      var current = true;
      ref.onDispose(() => current = false);
      ref.listen(adminAuthSessionScopeProvider, (_, _) => current = false);
      ref.listen(adminIdentityProvider, (_, _) => current = false);
      bool valid() =>
          current &&
          ref.read(adminAuthSessionScopeProvider) == scope &&
          identical(ref.read(adminRepositoryProvider), repository);
      bool permission(String name) =>
          valid() &&
          ref
                  .read(adminIdentityProvider)
                  .asData
                  ?.value
                  ?.permissions
                  .contains(name) ==
              true;
      final now = ref.watch(adminClockProvider),
          api = AdminReceiptNoticeContentSdk(
            rpc: (name, parameters) => repository.rpcMap(
              name,
              params: parameters,
              automaticRetry: false,
            ),
            actorId: scope.key.userId,
            sessionId: scope.key.sessionId,
            isCurrent: valid,
            canManage: () => permission('notifications.manage'),
            now: now,
          );
      return AdminReceiptNoticeContentAccess(
        api: api,
        repository: repository,
        actorId: scope.key.userId,
        sessionId: scope.key.sessionId,
        isCurrent: valid,
        canManage: () => permission('notifications.manage'),
        canListGroups: () =>
            permission('groups.read') && permission('settings.read'),
      );
    });

class AdminReceiptNoticePolicyHost extends ConsumerWidget {
  const AdminReceiptNoticePolicyHost({
    this.collectionId,
    this.onRecorded,
    super.key,
  });
  final String? collectionId;
  final VoidCallback? onRecorded;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(adminReceiptNoticeContentAccessProvider);
    if (access == null) return const _Unavailable();
    if (collectionId != null) {
      noticeUuid(collectionId);
      return _ControllerHost(
        access: access,
        collectionId: collectionId!,
        policy: true,
        onRecorded: onRecorded,
      );
    }
    if (!access.canListGroups()) return const _Unavailable();
    return _PolicySelector(
      key: ValueKey(access),
      access: access,
      onRecorded: onRecorded,
    );
  }
}

class AdminReceiptNoticeContentHost extends ConsumerWidget {
  const AdminReceiptNoticeContentHost({
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
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(adminReceiptNoticeContentAccessProvider);
    if (access == null) return const _Unavailable();
    noticeUuid(outboxId);
    noticeUuid(sourceSnapshotId);
    noticeUuid(collectionId);
    if (reversalSnapshotId != null) noticeUuid(reversalSnapshotId);
    return _ControllerHost(
      key: ValueKey((
        access,
        outboxId,
        sourceSnapshotId,
        collectionId,
        reversalSnapshotId,
      )),
      access: access,
      collectionId: collectionId,
      policy: false,
      outboxId: outboxId,
      sourceSnapshotId: sourceSnapshotId,
      reversalSnapshotId: reversalSnapshotId,
      onRecorded: onRecorded,
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();
  @override
  Widget build(BuildContext context) => const AdminDataSection(
    child: Padding(
      padding: EdgeInsets.all(20),
      child: Text(
        'Current email-owner access and payment, notification and system-health read permissions are required for notice evidence.',
      ),
    ),
  );
}

class _ControllerHost extends ConsumerStatefulWidget {
  const _ControllerHost({
    required this.access,
    required this.collectionId,
    required this.policy,
    this.outboxId,
    this.sourceSnapshotId,
    this.reversalSnapshotId,
    this.onRecorded,
    super.key,
  });
  final AdminReceiptNoticeContentAccess access;
  final String collectionId;
  final bool policy;
  final String? outboxId, sourceSnapshotId, reversalSnapshotId;
  final VoidCallback? onRecorded;
  @override
  ConsumerState<_ControllerHost> createState() => _ControllerHostState();
}

class _ControllerHostState extends ConsumerState<_ControllerHost> {
  AdminReceiptNoticeContentController? _controller;
  AdminReceiptNoticeContentStore? _store;
  AdminReceiptNoticeDispatchAccess? _dispatch;
  void _configure() {
    _controller?.dispose();
    final a = widget.access;
    final dispatch = _dispatch;
    _controller = AdminReceiptNoticeContentController(
      api: a.api,
      actorId: a.actorId,
      sessionId: a.sessionId,
      collectionId: widget.collectionId,
      policy: widget.policy,
      outboxId: widget.outboxId,
      sourceSnapshotId: widget.sourceSnapshotId,
      store: _store,
      now: ref.read(adminClockProvider),
      isCurrent: a.isCurrent,
      canManage: a.canManage,
      newRequestId: () => const Uuid().v4(),
      onRecorded: widget.onRecorded,
      preserveRecordedContent:
          widget.policy || dispatch == null || dispatch.store == null
          ? null
          : (original, recorded) async {
              await dispatch.preservePrepared(
                inspection: original.inspection,
                recorded: recorded,
                original: original,
              );
            },
    );
  }

  @override
  void didUpdateWidget(_ControllerHost old) {
    super.didUpdateWidget(old);
    if (old.access != widget.access ||
        old.collectionId != widget.collectionId ||
        old.outboxId != widget.outboxId ||
        old.sourceSnapshotId != widget.sourceSnapshotId ||
        old.reversalSnapshotId != widget.reversalSnapshotId ||
        old.policy != widget.policy) {
      _configure();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(adminReceiptNoticeContentStoreProvider);
    final dispatch = ref.watch(adminReceiptNoticeDispatchAccessProvider);
    if (_controller == null ||
        !identical(_store, store) ||
        !identical(_dispatch, dispatch)) {
      _store = store;
      _dispatch = dispatch;
      _configure();
    }
    return AdminReceiptNoticeContentView(
      key: ValueKey(_controller),
      controller: _controller!,
      reversalSnapshotId: widget.reversalSnapshotId,
    );
  }
}

class _PolicySelector extends StatefulWidget {
  const _PolicySelector({required this.access, this.onRecorded, super.key});
  final AdminReceiptNoticeContentAccess access;
  final VoidCallback? onRecorded;
  @override
  State<_PolicySelector> createState() => _PolicySelectorState();
}

class _PolicySelectorState extends State<_PolicySelector> {
  AdminListResult? _page;
  int _offset = 0, _generation = 0;
  bool _loading = false;
  String? _error, _selected;
  @override
  void initState() {
    super.initState();
    unawaited(_load(0));
  }

  Future<void> _load(int offset) async {
    if (_loading ||
        !widget.access.isCurrent() ||
        !widget.access.canListGroups()) {
      return;
    }
    final g = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _page = null;
      _selected = null;
    });
    try {
      final p = (await widget.access.repository.list(
        'admin_list_collections',
        limit: 25,
        offset: offset,
        countryCode: 'RW',
      )).validateWindow(limit: 25, offset: offset);
      for (final row in p.rows) {
        noticeUuid(row.id);
        if (row.extra['country_code'] != 'RW') noticeInvalid();
      }
      if (!mounted || g != _generation || !widget.access.isCurrent()) return;
      setState(() {
        _page = p;
        _offset = offset;
      });
    } catch (e) {
      if (!mounted || g != _generation) return;
      setState(() {
        _page = null;
        _error = noticeDenied(e)
            ? 'Current owner and group access are required.'
            : 'Rwanda groups could not be loaded. Refresh the group list.';
      });
    } finally {
      if (mounted && g == _generation) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _page, total = p?.total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminDataSection(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Receipt notice policy',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Select an authorized Rwanda group before reviewing its notice language and disclosure policy.',
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _loading ? null : () => _load(_offset),
                  child: const Text('Refresh groups'),
                ),
                if (_loading)
                  const LinearProgressIndicator(
                    semanticsLabel: 'Loading Rwanda groups',
                  ),
                if (_error != null)
                  Semantics(liveRegion: true, child: Text(_error!)),
                if (p != null && p.rows.isEmpty)
                  const Text('No Rwanda groups are available in this window.'),
                if (p != null && p.rows.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey((_offset, p)),
                    initialValue: _selected,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Rwanda group',
                    ),
                    items: [
                      for (final row in p.rows)
                        DropdownMenuItem(
                          value: row.id,
                          child: Text(
                            row.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _selected = v),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Groups ${_offset + 1}–${_offset + p.rows.length} of $total',
                      ),
                      OutlinedButton(
                        onPressed: _loading || _offset == 0
                            ? null
                            : () => _load((_offset - 25).clamp(0, _offset)),
                        child: const Text('Previous groups'),
                      ),
                      OutlinedButton(
                        onPressed: _loading || _offset + 25 >= total!
                            ? null
                            : () => _load(_offset + 25),
                        child: const Text('Next groups'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_selected != null)
          _ControllerHost(
            key: ValueKey((widget.access, _selected)),
            access: widget.access,
            collectionId: _selected!,
            policy: true,
            onRecorded: widget.onRecorded,
          ),
      ],
    );
  }
}
