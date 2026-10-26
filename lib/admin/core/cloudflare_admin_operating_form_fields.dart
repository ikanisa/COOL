part of 'cloudflare_admin_operating_pages.dart';

// Field rendering shares the owning form state and its existing update boundary.
extension _OperatingFormFields on _OperatingFormState {
  Widget _fieldWidget(_Field field) {
    if (widget.fixed.containsKey(field.key)) {
      return Text(
        '${field.label}: ${widget.initial['${field.key}_label'] ?? widget.fixed[field.key]}',
      );
    }
    if (field.lookup != null) {
      final kind = field.lookup!, rows = _lookups[kind] ?? [];
      final selected = _values[field.key];
      final options = [...rows];
      if (selected != null && !options.any((row) => row['id'] == selected)) {
        options.add({'id': selected, 'label': selected});
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey((field.key, selected)),
            initialValue: selected,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: field.label,
              helperText: field.hint,
            ),
            items: [
              if (!field.required)
                const DropdownMenuItem(value: '', child: Text('None')),
              for (final row in options)
                DropdownMenuItem(
                  value: row['id'] as String,
                  child: Text(
                    row['label'] as String,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _locked
                ? null
                : (value) => field.key == 'group_id'
                      ? _changedGroup(value)
                      : _changeField(
                          () => _values[field.key] = value == '' ? null : value,
                        ),
            validator: (value) =>
                field.required && (value == null || value.isEmpty)
                ? 'Select ${field.label.toLowerCase()}.'
                : null,
          ),
          if (_lookupLoading.contains(kind)) const LinearProgressIndicator(),
          if (_lookupErrors[kind] != null)
            _OperatingMessage(_lookupErrors[kind]!, error: true),
          if (!_lookupLoading.contains(kind) &&
              rows.isEmpty &&
              _lookupErrors[kind] == null)
            Text(
              {'payees', 'accounts', 'members'}.contains(kind) &&
                      _groupId == null
                  ? 'Choose a group first.'
                  : 'No eligible records found.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if ({
            'groups',
            'users',
            'payees',
            'accounts',
            'members',
            'sms_facts',
          }.contains(kind))
            Row(
              children: [
                Expanded(
                  child: TextField(
                    enabled: !_locked,
                    decoration: InputDecoration(
                      labelText: {'users', 'members'}.contains(kind)
                          ? 'Search name or Collect ID'
                          : 'Search ${operatingLabel(kind).toLowerCase()}',
                    ),
                    onSubmitted: (value) => _loadLookup(kind, search: value),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh ${field.label.toLowerCase()} choices',
                  onPressed: _locked ? null : () => _loadLookup(kind),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
        ],
      );
    }
    if (field.choices != null) {
      return DropdownButtonFormField<String>(
        key: ValueKey((field.key, _values[field.key])),
        initialValue: _values[field.key],
        isExpanded: true,
        decoration: InputDecoration(labelText: field.label),
        items: [
          if (!field.required)
            const DropdownMenuItem(value: '', child: Text('None')),
          for (final choice in field.choices!)
            DropdownMenuItem(
              value: choice,
              child: Text(operatingLabel(choice)),
            ),
        ],
        onChanged: _locked
            ? null
            : (value) => _changeField(
                () => _values[field.key] = value == '' ? null : value,
              ),
        validator: (value) => field.required && (value == null || value.isEmpty)
            ? 'Select ${field.label.toLowerCase()}.'
            : null,
      );
    }
    return TextFormField(
      controller: _controllers[field.key],
      enabled: !_locked,
      keyboardType: field.money
          ? TextInputType.number
          : field.multiline
          ? TextInputType.multiline
          : TextInputType.text,
      minLines: field.multiline ? 2 : 1,
      maxLines: field.multiline ? 4 : 1,
      decoration: InputDecoration(
        labelText: field.label,
        helperText: field.hint,
      ),
      validator: (value) => _validate(field, value),
    );
  }

  String _journalTotal(bool debit) {
    var total = BigInt.zero;
    for (final line in _lines) {
      final text = (debit ? line.debit : line.credit).text.trim();
      if (text.isEmpty) continue;
      final value = parseOperatingRwf(text, allowZero: true);
      if (value == null) return '—';
      total += BigInt.from(value);
    }
    return total.toString();
  }

  Widget _journalEditor() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Journal entries', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text('Whole RWF. Each line uses either debit or credit.'),
      const SizedBox(height: 12),
      Semantics(
        liveRegion: true,
        child: Text(
          'Debits RWF ${_journalTotal(true)} · Credits RWF ${_journalTotal(false)}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      if (_lookupLoading.contains('accounts')) const LinearProgressIndicator(),
      if (_lookupErrors['accounts'] != null)
        _OperatingMessage(_lookupErrors['accounts']!, error: true),
      if ((_lookups['accounts'] ?? []).isEmpty &&
          !_lookupLoading.contains('accounts'))
        const _OperatingMessage(
          'No active ledger accounts are available. Create them from the group detail first.',
        ),
      for (var index = 0; index < _lines.length; index++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: _journalLine(index),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _locked || _lines.length >= 100
              ? null
              : () => _changeField(() => _lines.add(_JournalLine())),
          icon: const Icon(Icons.add),
          label: const Text('Add line'),
        ),
      ),
      const SizedBox(height: 24),
    ],
  );

  Widget _journalLine(int index) {
    final line = _lines[index];
    final choices = [...?_lookups['accounts']];
    if (line.accountId != null &&
        !choices.any((row) => row['id'] == line.accountId)) {
      choices.add({'id': line.accountId, 'label': line.accountId});
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Line ${index + 1}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            if (_lines.length > 2)
              IconButton(
                tooltip: 'Remove line ${index + 1}',
                onPressed: _locked
                    ? null
                    : () => _changeField(() {
                        _lines.removeAt(index).dispose();
                      }),
                icon: const Icon(Icons.close),
              ),
          ],
        ),
        DropdownButtonFormField<String>(
          key: ValueKey((line, line.accountId)),
          initialValue: line.accountId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Ledger account'),
          items: [
            for (final row in choices)
              DropdownMenuItem(
                value: row['id'] as String,
                child: Text(
                  row['label'] as String,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _locked
              ? null
              : (value) => _changeField(() => line.accountId = value),
          validator: (value) =>
              value == null ? 'Select an active account.' : null,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final side in [
              (line.debit, 'Debit (RWF)'),
              (line.credit, 'Credit (RWF)'),
            ])
              SizedBox(
                width: 220,
                child: TextFormField(
                  controller: side.$1,
                  enabled: !_locked,
                  onChanged: (_) => _changeField(() {}),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: side.$2),
                  validator: (value) =>
                      value?.trim().isNotEmpty == true &&
                          parseOperatingRwf(value!, allowZero: true) == null
                      ? 'Enter an exact whole RWF value.'
                      : null,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: line.description,
          enabled: !_locked,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Line description (optional)',
          ),
        ),
      ],
    );
  }
}
