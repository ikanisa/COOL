part of 'cloudflare_admin_operating_pages.dart';

/// Private text stays in this mounted form. Reload recovery retains only its
/// digest and original key, and never resends without an explicit user action.
class CloudflareOperatorNotes extends ConsumerStatefulWidget {
  const CloudflareOperatorNotes({
    required this.type,
    required this.id,
    super.key,
  });
  final String type, id;
  @override
  ConsumerState<CloudflareOperatorNotes> createState() => _OperatorNotesState();
}

class _OperatorNotesState extends ConsumerState<CloudflareOperatorNotes> {
  static const _family = 'operator-note';
  static const _schema = AdminPendingAttemptSchema(fields: {'body_sha256'});
  final _body = TextEditingController();
  late final Object? _authority;
  Future<CloudflareOperatorNotePage>? _future;
  String? _key, _digest, _error, _message;
  bool _busy = false, _retryAllowed = false;
  int _offset = 0;
  String get _resource => '${widget.type}:${widget.id}';
  String get _permission =>
      widget.type == 'groups' ? 'collections.read' : 'users.read';
  bool get _current {
    final user = ref.read(cloudflareAdminSessionProvider).asData?.value;
    return mounted &&
        user != null &&
        user.authorityKey == _authority &&
        user.expiresAt.isAfter(DateTime.now()) &&
        user.permissions.contains(_permission);
  }

  String _hash(String value) =>
      sha256.convert(utf8.encode(value.trim())).toString();
  @override
  void initState() {
    super.initState();
    _authority = ref
        .read(cloudflareAdminSessionProvider)
        .asData
        ?.value
        ?.authorityKey;
    if (_current) {
      final saved = ref
          .read(adminPendingAttemptStoreProvider)
          .restore(family: _family, resourceId: _resource, schema: _schema);
      if (saved != null) {
        _key = saved.requestKey;
        _digest = saved.intent['body_sha256'] as String?;
      }
      _load();
    }
  }

  void _load() {
    _future = _repository(
      ref,
    ).operatorNotes(widget.type, widget.id, offset: _offset);
  }

  void _clearAttempt() => ref
      .read(adminPendingAttemptStoreProvider)
      .clear(family: _family, resourceId: _resource);
  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_current || _busy || (_key != null && !_retryAllowed)) return;
    final body = _body.text.trim();
    if (body.isEmpty || body.length > 2000) {
      setState(() => _error = 'Enter a note of up to 2000 characters.');
      return;
    }
    final hash = _hash(body);
    if (_key != null && hash != _digest) {
      setState(
        () => _error =
            'Re-enter the exact original note before retrying this request.',
      );
      return;
    }
    final key = _key ?? const Uuid().v4();
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final store = ref.read(adminPendingAttemptStoreProvider);
      store.retain(
        family: _family,
        resourceId: _resource,
        requestKey: key,
        permission: _permission,
        intent: {'body_sha256': hash},
        schema: _schema,
      );
      if (!store.storageAvailable) {
        throw const AdminAccountException(
          'Request recovery is unavailable in this browser. Restore it before recording a note.',
        );
      }
      _key = key;
      _digest = hash;
      _retryAllowed = false;
      await _repository(
        ref,
      ).recordOperatorNote(widget.type, widget.id, key: key, body: body);
      if (!_current) return;
      _clearAttempt();
      setState(() {
        _key = null;
        _digest = null;
        _body.clear();
        _message = 'Operator note recorded';
        _offset = 0;
        _load();
      });
    } catch (error) {
      if (_current) {
        setState(
          () => _error = _key == null
              ? _safeOperatingError(error)
              : 'The result is unconfirmed. Check the original request before recording another note.',
        );
      }
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  Future<void> _check() async {
    if (!_current || _busy || _key == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _repository(ref).operatingRequest(_key!);
      if (!_current) return;
      if (result['status'] == 'succeeded') {
        final receipt = CloudflareOperationReceipt.parse(
          Map<String, dynamic>.from(result['receipt'] as Map),
        );
        if (receipt.resourceType != 'operator_notes' || receipt.version != 1) {
          throw const FormatException();
        }
        _clearAttempt();
        setState(() {
          _key = null;
          _digest = null;
          _body.clear();
          _message = 'Operator note recorded';
          _offset = 0;
          _load();
        });
      } else if (result['status'] == 'cancelled') {
        _clearAttempt();
        setState(() {
          _key = null;
          _digest = null;
          _body.clear();
          _message = 'The original request was cancelled.';
        });
      } else {
        setState(() {
          _retryAllowed = result['status'] == 'not_found';
          _message = _retryAllowed
              ? 'No completed request was found. Re-enter the exact original note to retry with its original reference.'
              : 'The original request is still unconfirmed.';
        });
      }
    } catch (error) {
      if (_current) setState(() => _error = _safeOperatingError(error));
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(cloudflareAdminSessionProvider);
    ref.listen(adminRealtimeTickProvider, (_, _) {
      if (_current && !_busy) setState(_load);
    });
    if (!_current) {
      return const _OperatingMessage(
        'Reopen this record with your current session.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Support notes', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(
          controller: _body,
          minLines: 2,
          maxLines: 6,
          maxLength: 2000,
          enabled: !_busy && (_key == null || _retryAllowed),
          decoration: const InputDecoration(
            labelText: 'Support note',
            helperText:
                'Record relevant facts. Do not include passwords or verification codes.',
          ),
        ),
        if (_key != null) ...[
          SelectableText('Request reference: $_key'),
          Wrap(
            spacing: 12,
            children: [
              OutlinedButton(
                onPressed: _busy ? null : _check,
                child: const Text('Check original note request'),
              ),
              TextButton(
                onPressed: () => context.go('/admin/requests?key=$_key'),
                child: const Text('Open request history'),
              ),
            ],
          ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: _busy || (_key != null && !_retryAllowed) ? null : _send,
            child: Text(_key == null ? 'Record note' : 'Retry original note'),
          ),
        ),
        if (_error != null) _OperatingMessage(_error!, error: true),
        if (_message != null) _OperatingMessage(_message!),
        const SizedBox(height: 20),
        FutureBuilder<CloudflareOperatorNotePage>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const AdminLoadingState(title: 'Loading support notes');
            }
            if (snapshot.hasError) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _OperatingMessage(
                    _safeOperatingError(snapshot.error!),
                    error: true,
                  ),
                  TextButton(
                    onPressed: () => setState(_load),
                    child: const Text('Refresh notes'),
                  ),
                ],
              );
            }
            final page = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (page.rows.isEmpty)
                  const Text('No support notes on this page.')
                else
                  AdminDataTable(
                    tableLabel: 'Support notes on this page',
                    rows: [
                      for (final row in page.rows)
                        AdminTableRowData(
                          id: row['id'] as String,
                          title: row['body'] as String,
                          subtitle: '',
                          status: '',
                          amount: '',
                          extra: row,
                        ),
                    ],
                    columns: [
                      AdminTableColumn(
                        label: 'Note',
                        value: (r) => r.title,
                        allowNaturalHeight: true,
                        cellBuilder: (r) => SizedBox(
                          width: 420,
                          child: MergeSemantics(
                            child: Semantics(
                              label: 'Note:',
                              child: SelectableText(r.title),
                            ),
                          ),
                        ),
                      ),
                      AdminTableColumn(
                        label: 'Recorded by',
                        value: (r) => r.extra['author_name'] as String,
                      ),
                      AdminTableColumn(
                        label: 'Recorded at',
                        value: (r) => r.extra['created_at'] as String,
                      ),
                    ],
                  ),
                Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('${page.total} support notes'),
                    TextButton(
                      onPressed: _offset == 0
                          ? null
                          : () => setState(() {
                              _offset = (_offset - 25).clamp(0, 10000);
                              _load();
                            }),
                      child: const Text('Previous notes'),
                    ),
                    TextButton(
                      onPressed:
                          _offset + page.rows.length >= page.total ||
                              _offset >= 10000
                          ? null
                          : () => setState(() {
                              _offset += 25;
                              _load();
                            }),
                      child: const Text('Next notes'),
                    ),
                    TextButton(
                      onPressed: () => setState(_load),
                      child: const Text('Refresh notes'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
