part of 'cloudflare_canonical_reconciliation_pages.dart';

class _CanonicalRelatedRecords extends StatelessWidget {
  const _CanonicalRelatedRecords({
    required this.detail,
    required this.user,
    required this.busy,
    required this.pending,
    required this.onPage,
    required this.onReview,
    required this.onEvidence,
  });
  final CanonicalReconciliationDetail detail;
  final CloudflareAdminUser? user;
  final bool busy, pending;
  final void Function(String, int) onPage;
  final void Function(CanonicalReconciliationProposal) onReview;
  final void Function(Map<String, dynamic>) onEvidence;
  Widget _proposals(ReconciliationPage<Map<String, dynamic>> page) {
    final proposals = {
      for (final row in page.rows)
        row['id'] as String: CanonicalReconciliationProposal.parse(
          row,
          transactionId: detail.id,
          evidenceId: detail.transaction['evidence_id'] as String,
        ),
    };
    return _records(
      'Attribution proposals',
      [
        for (final proposal in proposals.values)
          {
            ...proposal.values,
            'recorded_name': proposal.identity?.name,
            'recorded_momo': proposal.identity?.number,
          },
      ],
      const {
        'member_public_id': 'Member ID',
        'recorded_name': 'Recorded name',
        'recorded_momo': 'Recorded MoMo',
        'status': 'Decision',
        'reason': 'Proposal reason',
        'review_reason': 'Review reason',
        'created_at': 'Proposed',
        'reviewed_at': 'Reviewed',
      },
      trailing: (row) {
        final proposal = proposals[row['id']]!;
        return detail.canReview &&
                proposal.values['status'] == 'proposed' &&
                proposal.snapshotAvailable &&
                proposal.values['proposed_by_principal_id'] !=
                    detail.principalId
            ? TextButton(
                onPressed: busy || pending || !_fresh(user)
                    ? null
                    : () => onReview(proposal),
                child: const Text('Independent review'),
              )
            : const SizedBox.shrink();
      },
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final entry in detail.related.entries) ...[
        Text(_label(entry.key), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (entry.value.rows.isEmpty)
          Text('No ${entry.key.replaceAll('_', ' ')} recorded.')
        else if (entry.key == 'proposals')
          _proposals(entry.value)
        else
          _records(
            _label(entry.key),
            entry.value.rows,
            entry.key == 'evidence'
                ? const {
                    'authenticity': 'Evidence basis',
                    'reference': 'Reference',
                    'sha256': 'SHA-256',
                    'size_bytes': 'Bytes',
                    'observed_at': 'Observed',
                    'retained_until': 'Retained until',
                    'legal_hold': 'Legal hold',
                  }
                : const {
                    'kind': 'Entry',
                    'signed_amount_rwf': 'Signed amount (RWF)',
                    'member_user_id': 'Member',
                    'posted_at': 'Recorded',
                    'reverses_entry_id': 'Reverses entry',
                    'settlement_status': 'Provider settlement',
                  },
            trailing:
                entry.key == 'evidence' &&
                    user?.permissions.contains('payments.evidence.read') == true
                ? (row) => TextButton(
                    onPressed: busy ? null : () => onEvidence(row),
                    child: const Text('Read retained evidence'),
                  )
                : null,
          ),
        _pager(entry.value, busy, (offset) => onPage(entry.key, offset)),
        const SizedBox(height: 20),
      ],
    ],
  );
}
