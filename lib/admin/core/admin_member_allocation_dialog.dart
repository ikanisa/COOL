import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/collect_colors.dart';
import '../shared/components/admin_data_listing.dart';
import 'admin_existing_member_allocation.dart';

/// Searches registered identities only; an entered number never becomes a
/// member or a payment target until an eligible server result is selected.
class AdminMemberAllocationDialog extends StatefulWidget {
  const AdminMemberAllocationDialog({
    required this.api,
    required this.eventId,
    required this.transactionLabel,
    required this.isCurrent,
    super.key,
  });
  final AdminExistingMemberAllocationApi api;
  final String eventId, transactionLabel;
  final bool Function() isCurrent;

  @override
  State<AdminMemberAllocationDialog> createState() =>
      _AdminMemberAllocationDialogState();
}

class _AdminMemberAllocationDialogState
    extends State<AdminMemberAllocationDialog> {
  final _query = TextEditingController();
  final _reason = TextEditingController();
  Timer? _debounce;
  AdminAllocationMemberPage? _results;
  AdminAllocationMember? _selected;
  String? _error;
  int _request = 0, _offset = 0;
  bool _loading = false, _confirmed = false, _saving = false;
  bool _writeAttempted = false;
  static const _pageSize = 10;

  bool get _current => mounted && widget.isCurrent();
  bool get _canAllocate =>
      _current &&
      !_saving &&
      !_loading &&
      !_writeAttempted &&
      _confirmed &&
      _selected?.eligible == true &&
      _reason.text.trim().length >= 8 &&
      _reason.text.trim().length <= 500;

  @override
  void dispose() {
    _debounce?.cancel();
    _request++;
    _query.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _queryChanged(String _) {
    _debounce?.cancel();
    _request++;
    setState(() {
      _selected = null;
      _confirmed = false;
      _results = null;
      _error = null;
      _offset = 0;
      _loading = _query.text.trim().length >= 3;
    });
    if (_loading) {
      _debounce = Timer(const Duration(milliseconds: 350), () => _search(0));
    }
  }

  Future<void> _search(int offset) async {
    _debounce?.cancel();
    if (!_current || _saving || _writeAttempted) return;
    final query = _query.text.trim();
    if (query.length < 3) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _selected = null;
      _confirmed = false;
      _results = null;
      _error = null;
    });
    try {
      final result = await widget.api.search(
        eventId: widget.eventId,
        query: query,
        limit: _pageSize,
        offset: offset,
      );
      if (!_current || request != _request) return;
      setState(() {
        _results = result;
        _offset = offset;
        _loading = false;
      });
    } catch (_) {
      if (!_current || request != _request) return;
      setState(() {
        _loading = false;
        _error = 'Member search could not be completed. Search again.';
      });
    }
  }

  Future<void> _allocate() async {
    if (!_canAllocate) return;
    final selected = _selected!;
    setState(() {
      _saving = true;
      _writeAttempted = true;
      _error = null;
    });
    try {
      final receipt = await widget.api.allocate(
        eventId: widget.eventId,
        member: selected,
        reason: _reason.text,
      );
      if (!mounted || !widget.isCurrent()) return;
      Navigator.of(context).pop(receipt);
    } catch (_) {
      if (!_current) return;
      setState(() {
        _saving = false;
        _error =
            'Allocation was not confirmed. Close this dialog and refresh '
            'the transaction to check its state before trying again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: const Text('Allocate transaction'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.transactionLabel),
              const SizedBox(height: 16),
              TextField(
                controller: _query,
                autofocus: true,
                enabled: !_saving && !_writeAttempted,
                autocorrect: false,
                maxLength: 80,
                textInputAction: TextInputAction.search,
                onChanged: _queryChanged,
                onSubmitted: (_) => _search(0),
                decoration: const InputDecoration(
                  labelText: 'Member MoMo number or name',
                  hintText: 'Search an existing member',
                  helperText:
                      'Enter at least 3 characters. Registered numbers only.',
                  helperMaxLines: 3,
                  prefixIcon: Icon(Icons.search),
                  counterText: '',
                ),
              ),
              if (_loading) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  label: 'Searching registered members',
                  child: const LinearProgressIndicator(),
                ),
              ],
              if (_results case final results?) ...[
                const SizedBox(height: 12),
                if (results.total == 0)
                  Semantics(
                    liveRegion: true,
                    child: const Text(
                      'No registered member found. Check the number or name.',
                    ),
                  ),
                if (results.rows.isNotEmpty)
                  Semantics(
                    container: true,
                    label:
                        'Registered member matches table, ${results.rows.length} rows',
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        key: const Key('allocation-member-matches-table'),
                        showCheckboxColumn: false,
                        dataRowMinHeight: 64,
                        dataRowMaxHeight: double.infinity,
                        columns: const [
                          DataColumn(label: Text('Name')),
                          DataColumn(label: Text('MoMo number')),
                          DataColumn(label: Text('Group')),
                          DataColumn(label: Text('Collect ID')),
                          DataColumn(label: Text('Eligibility')),
                          DataColumn(label: Text('Select')),
                        ],
                        rows: [
                          for (final member in results.rows)
                            DataRow(
                              key: ValueKey(member.key),
                              selected: selected?.key == member.key,
                              cells: [
                                DataCell(
                                  Text(member.displayName, softWrap: false),
                                ),
                                DataCell(
                                  Text(member.momoNumber, softWrap: false),
                                ),
                                DataCell(
                                  Text(member.collectionName, softWrap: false),
                                ),
                                DataCell(
                                  Text(member.collectId, softWrap: false),
                                ),
                                DataCell(
                                  Text(
                                    member.eligible
                                        ? 'Eligible'
                                        : member.unavailableReason ??
                                              'No eligible payment match for this member.',
                                    softWrap: false,
                                  ),
                                ),
                                DataCell(
                                  Semantics(
                                    label:
                                        'Select member ${member.displayName}, Collect ID ${member.collectId}, group ${member.collectionName}',
                                    child: OutlinedButton(
                                      key: ValueKey(
                                        'allocation-select-${member.key}',
                                      ),
                                      onPressed:
                                          !member.eligible ||
                                              _saving ||
                                              _writeAttempted
                                          ? null
                                          : () => setState(() {
                                              _selected = member;
                                              _confirmed = false;
                                            }),
                                      child: Text(
                                        selected?.key == member.key
                                            ? 'Selected'
                                            : 'Select',
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                if (results.total > _pageSize)
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${_offset + 1}–${_offset + results.rows.length} of ${results.total} matches',
                      ),
                      TextButton(
                        onPressed: _offset == 0 || _saving || _writeAttempted
                            ? null
                            : () => _search(_offset - _pageSize),
                        child: const Text('Previous matches'),
                      ),
                      TextButton(
                        onPressed:
                            _offset + _pageSize >= results.total ||
                                _saving ||
                                _writeAttempted
                            ? null
                            : () => _search(_offset + _pageSize),
                        child: const Text('Next matches'),
                      ),
                    ],
                  ),
              ],
              if (selected != null) ...[
                const SizedBox(height: 16),
                const Text('Confirm member details'),
                const SizedBox(height: 8),
                AdminDataFieldRow(label: 'Member', value: selected.displayName),
                AdminDataFieldRow(
                  label: 'MoMo number',
                  value: selected.momoNumber,
                ),
                if (selected.momoRegisteredName != null)
                  AdminDataFieldRow(
                    label: 'Registered MoMo name',
                    value: selected.momoRegisteredName!,
                  ),
                AdminDataFieldRow(
                  label: 'Group',
                  value: selected.collectionName,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    'I confirm the member name and MoMo number.',
                  ),
                  value: _confirmed,
                  onChanged: _saving || _writeAttempted
                      ? null
                      : (value) => setState(() => _confirmed = value == true),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _reason,
                enabled: !_saving && !_writeAttempted,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Allocation reason',
                  helperText:
                      'Required for the audit trail. At least 8 characters.',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Independent provider confirmation is required before ledger posting.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: context.collectColors.dangerForeground,
                    ),
                  ),
                ),
              ],
              if (_saving) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _canAllocate ? _allocate : null,
            child: Text(_saving ? 'Allocating…' : 'Allocate transaction'),
          ),
        ],
      ),
    );
  }
}
