part of 'cloudflare_canonical_reconciliation_pages.dart';

class _CanonicalMemberForm extends StatefulWidget {
  const _CanonicalMemberForm({
    required this.api,
    required this.detail,
    required this.user,
    required this.disabled,
    required this.onProposed,
  });
  final CanonicalReconciliationApi api;
  final CanonicalReconciliationDetail detail;
  final CloudflareAdminUser? user;
  final bool disabled;
  final Future<void> Function(CanonicalFinancialAttempt) onProposed;
  @override
  State<_CanonicalMemberForm> createState() => _CanonicalMemberFormState();
}

class _CanonicalMemberFormState extends State<_CanonicalMemberForm> {
  final _search = TextEditingController(), _reason = TextEditingController();
  late Future<ReconciliationPage<ReconciliationMember>> _members;
  ReconciliationMember? _selected;
  String _applied = '';
  String? _error;
  bool _acknowledged = false, _reviewing = false;
  bool get _busy => widget.disabled || _reviewing;
  @override
  void initState() {
    super.initState();
    _members = widget.api.members(widget.detail);
  }

  @override
  void didUpdateWidget(covariant _CanonicalMemberForm old) {
    super.didUpdateWidget(old);
    if (old.api != widget.api ||
        old.detail.id != widget.detail.id ||
        old.detail.transaction['version'] !=
            widget.detail.transaction['version'] ||
        old.detail.group['version'] != widget.detail.group['version']) {
      _search.clear();
      _reason.clear();
      _selected = null;
      _acknowledged = false;
      _applied = '';
      _error = null;
      _members = widget.api.members(widget.detail);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    if (_busy || _selected == null || !_acknowledged) return;
    setState(() {
      _reviewing = true;
      _error = null;
    });
    try {
      final attempt = widget.api.propose(
        widget.detail,
        _selected!,
        _reason.text,
      );
      await widget.onProposed(attempt);
    } catch (error) {
      if (mounted) setState(() => _error = _safeError(error));
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Propose member attribution',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      Text(
        'Amount to attribute: ${adminFormatWholeAmount(widget.detail.transaction['amount_rwf'])} RWF',
      ),
      TextField(
        controller: _search,
        maxLength: 200,
        decoration: const InputDecoration(
          labelText: 'Find a group member',
          hintText: 'Member ID, recorded name or MoMo number',
        ),
        onSubmitted: _busy
            ? null
            : (value) => setState(() {
                _applied = value.trim();
                _selected = null;
                _acknowledged = false;
                _members = widget.api.members(widget.detail, search: _applied);
              }),
      ),
      FutureBuilder<ReconciliationPage<ReconciliationMember>>(
        future: _members,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const AdminLoadingState(title: 'Loading current members');
          }
          if (snapshot.hasError) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Note(_safeError(snapshot.error!), error: true),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(
                          () => _members = widget.api.members(
                            widget.detail,
                            search: _applied,
                          ),
                        ),
                  child: const Text('Try member lookup again'),
                ),
              ],
            );
          }
          final page = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (page.rows.isEmpty)
                const Text('No eligible members match this search.')
              else
                _records(
                  'Current group members',
                  [
                    for (final member in page.rows)
                      {'id': member.id, ...member.values},
                  ],
                  const {
                    'public_id': 'Member ID',
                    'display_name': 'Recorded name',
                    'momo_provider': 'MoMo provider',
                    'momo_number': 'MoMo number',
                    'momo_pay_code': 'MoMo code',
                  },
                  trailing: (row) => TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _selected = page.rows.firstWhere(
                              (member) => member.id == row['id'],
                            );
                            _acknowledged = false;
                          }),
                    child: Text(
                      _selected?.id == row['id']
                          ? 'Selected member'
                          : 'Select member',
                    ),
                  ),
                ),
              _pager(
                page,
                _busy,
                (offset) => setState(() {
                  _members = widget.api.members(
                    widget.detail,
                    search: _applied,
                    offset: offset,
                  );
                  _acknowledged = false;
                }),
              ),
            ],
          );
        },
      ),
      if (_selected != null)
        _records(
          'Selected recorded identity',
          [
            {'id': _selected!.id, ..._selected!.values},
          ],
          const {
            'public_id': 'Member ID',
            'display_name': 'Recorded name',
            'momo_provider': 'MoMo provider',
            'momo_number': 'MoMo number',
            'momo_pay_code': 'MoMo code',
          },
        ),
      CheckboxListTile(
        value: _acknowledged,
        onChanged: _selected == null || _busy
            ? null
            : (value) => setState(() => _acknowledged = value!),
        title: const Text(
          'I checked this member’s recorded MoMo identity against the retained evidence.',
        ),
      ),
      TextField(
        controller: _reason,
        maxLength: 500,
        minLines: 2,
        maxLines: 4,
        enabled: !_busy,
        decoration: const InputDecoration(
          labelText: 'Reason for this attribution',
        ),
      ),
      if (_error != null) _Note(_error!, error: true),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(
          onPressed:
              _busy ||
                  !_acknowledged ||
                  _selected == null ||
                  !_fresh(widget.user)
              ? null
              : _prepare,
          child: const Text('Review member proposal'),
        ),
      ),
    ],
  );
}
