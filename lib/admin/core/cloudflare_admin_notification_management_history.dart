part of 'cloudflare_admin_notification_management_page.dart';

/// A separate per-tab namespace prevents the shared all-permission binding
/// from removing an unknown self-access reference when notification grants
/// change. The canonical principal is part of the namespace, not authority.
class _ReferenceStorage implements AdminPendingAttemptStorage {
  _ReferenceStorage(this.storage, CloudflareAdminUser? user)
    : prefix =
          'collect.admin.notification-management.${user?.id}.${user?.sessionId}.${user?.principalId}';
  final AdminPendingAttemptStorage storage;
  final String prefix;
  String _key(String key) => '$prefix.$key';
  @override
  String? read(String key) => storage.read(_key(key));
  @override
  void write(String key, String value) => storage.write(_key(key), value);
  @override
  void remove(String key) => storage.remove(_key(key));
}

/// This copy can retain metadata only under a permission the actual Owner
/// already has. Notification grants never become checkpoint authority.
CloudflareAdminUser? _checkpointActor(CloudflareAdminUser? user) {
  if (user == null ||
      user.role != AdminAccountRole.owner ||
      user.principalId == null ||
      !user.permissions.contains('admin_users.manage')) {
    return null;
  }
  return CloudflareAdminUser(
    id: user.id,
    email: user.email,
    role: user.role,
    sessionId: user.sessionId,
    expiresAt: user.expiresAt,
    permissions: const ['admin_users.manage'],
    principalId: user.principalId,
    assuranceLevel: user.assuranceLevel,
    mfaAt: user.mfaAt,
    usesEmailVerification: user.usesEmailVerification,
    emailVerifiedAt: user.emailVerifiedAt,
    financialModel: user.financialModel,
  );
}

class _Pending {
  _Pending(
    this.requestId,
    this.action,
    this.resourceId, {
    this.original,
    this.expectedDecisionRevision,
  }) {
    if (action == 'access' && expectedDecisionRevision == null) {
      status =
          'Expected access decision revision was not retained; preserve this original UUID for reconciliation';
    }
  }
  final String requestId, action, resourceId;
  // Correlation metadata never reconstructs an original command or authority.
  final int? expectedDecisionRevision;
  String get storageId => '$action:$resourceId';
  NotificationManagementOperation? original;
  bool unresolved = true;
  String status = 'Original result requires reconciliation';
  List<(String, String)> facts = const [];
}

class _HistoryReadback {
  const _HistoryReadback({
    required this.requestId,
    required this.kind,
    this.receipt,
    this.currentAccess,
  });
  final String requestId;
  final NotificationManagementHistoryKind kind;
  final NotificationManagementReceipt? receipt;
  final NotificationManagementAccessState? currentAccess;
}

List<Widget> _historyWidgets(_ManagementState state, BuildContext context) {
  final sequence = state._historySequence;
  final enabled =
      state._current &&
      !state._busy &&
      !state._historyLoading &&
      state._api.canReadHistory;
  final page = state._history, view = state._historyReadback;
  return [
    _heading(context, 'Request history'),
    const Text('Review recorded requests from this sign-in.'),
    const _ContextDetails(
      key: Key('notification-management-history-context'),
      title: 'History details',
      semanticLabel: 'Request history scope details',
      fields: [
        (
          'History and local references',
          'Server-recorded history is separate from this tab’s original request references.',
        ),
        ('Access', 'Metadata does not grant access.'),
        ('Replay, cancellation and sending', 'Not authorized by history.'),
        ('Missing history', 'Never resolves an original UUID.'),
        (
          'Materialization plans',
          'Metadata only here. No batch preparation, resume or sender action is available.',
        ),
      ],
    ),
    const SizedBox(height: 12),
    Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          key: const Key('notification-management-history-load'),
          onPressed: enabled
              ? () => state._loadHistory(expectedSequence: sequence)
              : null,
          icon: const Icon(Icons.history),
          label: Text(
            page == null
                ? 'Load recorded request history'
                : 'Refresh recorded request history',
          ),
        ),
        OutlinedButton(
          key: const Key('notification-management-history-previous'),
          onPressed: enabled && state._historyBack.isNotEmpty
              ? () => state._loadHistory(
                  previous: true,
                  expectedSequence: sequence,
                )
              : null,
          child: const Text('Previous history page'),
        ),
        OutlinedButton(
          key: const Key('notification-management-history-next'),
          onPressed: enabled && page?.nextCursor != null
              ? () => state._loadHistory(next: true, expectedSequence: sequence)
              : null,
          child: const Text('Next history page'),
        ),
      ],
    ),
    if (state._historyLoading)
      const LinearProgressIndicator(
        semanticsLabel: 'Loading recorded request history',
      ),
    if (state._historyError != null)
      _Message(state._historyError!, error: true),
    if (page != null) ...[
      Text(
        'History page ${state._historyBack.length + 1} · up to 25 recorded requests',
      ),
      if (page.items.isEmpty)
        const _Message(
          'No recorded requests on this page. Pending requests still need checking.',
        )
      else
        AdminDataTable(
          tableLabel: 'Server-recorded assisted SMS request history',
          rows: [
            for (final item in page.items)
              _row(item.requestId, {
                'request_id': item.requestId,
                'kind': _historyKind(item.kind),
                'recorded_at': adminKigaliDateTime(item.recordedAt),
                'recorded_outcome': item.recordedOutcome == 'plan_recorded'
                    ? 'Plan recorded'
                    : 'Decision recorded',
                'lookup':
                    item.kind ==
                        NotificationManagementHistoryKind.materialization
                    ? 'Read-only plan status unavailable here'
                    : state._canViewHistory(item)
                    ? 'Available under current access'
                    : 'Review and record permission required',
              }),
          ],
          columns: [
            AdminTableColumn(
              label: 'Recorded status',
              value: (_) => 'View recorded status',
              cellBuilder: (row) {
                final item = page.items.firstWhere(
                  (item) => item.requestId == row.id,
                );
                return OutlinedButton.icon(
                  key: ValueKey('management-history-status:${item.requestId}'),
                  onPressed: enabled && state._canViewHistory(item)
                      ? () => state._viewHistory(item, sequence)
                      : null,
                  icon: const Icon(Icons.manage_search),
                  label: Text(
                    item.kind ==
                            NotificationManagementHistoryKind.materialization
                        ? 'Status unavailable'
                        : 'View recorded status',
                  ),
                );
              },
            ),
            _column('request_id', 'Original UUID'),
            _column('kind', 'Kind'),
            _column('recorded_at', 'Recorded at'),
            _column('recorded_outcome', 'Recorded outcome'),
            _column('lookup', 'Lookup availability'),
          ],
        ),
    ],
    if (view != null) ...[
      _heading(context, 'Read-only original request status'),
      if (view.receipt case final receipt?)
        AdminRecordFactsTable(
          semanticLabel:
              'Server recorded historical decision ${view.requestId}',
          fields: [
            ('Original UUID', view.requestId),
            ('Recorded request kind', _historyKind(view.kind)),
            ..._primaryDecisionFacts(_receiptFacts(receipt)),
          ],
        )
      else
        const _Message(
          'No recorded result was observed. The request may still be in flight; this does not clear any local original UUID.',
        ),
      if (view.currentAccess case final access?)
        AdminRecordFactsTable(
          semanticLabel:
              'Current access observed with recorded request ${view.requestId}',
          fields: [
            ('Current access decision revision', '${access.decisionRevision}'),
            (
              'View assisted SMS jobs',
              access.readGranted ? 'Granted' : 'Not granted',
            ),
            (
              'Review and record assisted SMS operations',
              access.manageGranted ? 'Granted' : 'Not granted',
            ),
            (
              'Both operational grants present',
              access.canOperate ? 'Yes' : 'No',
            ),
          ],
        ),
      _ContextDetails(
        key: ValueKey('management-history-details:${view.requestId}'),
        title: 'Recorded request details',
        semanticLabel: 'Recorded request technical details ${view.requestId}',
        fields: [
          ('Original UUID', view.requestId),
          if (view.receipt case final receipt?)
            ..._secondaryDecisionFacts(_receiptFacts(receipt)),
          if (view.currentAccess case final access?) ...[
            ('Owner account ID', access.adminId),
            ('Canonical principal ID', access.principalId),
          ],
          ('Observation supplies replay authority', 'No'),
        ],
      ),
      if (view.receipt is NotificationManagementPolicyReceipt) ...[
        const Text(
          'This receipt records the original policy decision. Current policy requires its own read.',
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed:
                state._current &&
                    !state._busy &&
                    !state._historyLoading &&
                    state._api.canManagePolicy
                ? () => state._loadHistoryPolicy(view)
                : null,
            child: const Text('Check current policy for recorded collection'),
          ),
        ),
        if (state._historyCurrentPolicy case final policy?)
          AdminRecordFactsTable(
            semanticLabel:
                'Current policy observed with recorded request ${view.requestId}',
            fields: [
              ('Collection ID', policy.collectionId),
              ('Current revision', '${policy.revision}'),
              ('Currently enabled', policy.enabled ? 'Yes' : 'No'),
              ('Configured', policy.configured ? 'Yes' : 'No'),
            ],
          ),
      ],
    ],
  ];
}

String _historyKind(NotificationManagementHistoryKind kind) => switch (kind) {
  NotificationManagementHistoryKind.access => 'Self-access',
  NotificationManagementHistoryKind.policy => 'Collection policy',
  NotificationManagementHistoryKind.materialization => 'Materialization plan',
};

List<(String, String)> _receiptFacts(NotificationManagementReceipt receipt) => [
  ('Recorded state only', 'Yes; not current authority'),
  if (receipt is NotificationManagementAccessReceipt) ...[
    ('Recorded access enabled', receipt.enabled ? 'Yes' : 'No'),
    ('Recorded access decision revision', '${receipt.decisionRevision}'),
    ('Grant transaction ID', receipt.grantTransactionId),
    ('Decision SHA-256', receipt.decisionSha256),
    ('Recorded at', adminKigaliDateTime(receipt.recordedAt)),
  ],
  if (receipt is NotificationManagementPolicyReceipt) ...[
    ('Collection ID', receipt.collectionId),
    ('Recorded policy enabled', receipt.enabled ? 'Yes' : 'No'),
    ('Recorded revision', '${receipt.revision}'),
    ('Decision SHA-256', receipt.recordedOwnerDecisionSha256),
    ('Recorded at', adminKigaliDateTime(receipt.recordedAt)),
  ],
];

List<Widget> _currentAccessWidgets(
  _ManagementState state,
  BuildContext context,
) => [
  if (!state._references.storageAvailable)
    _Message(state._references.storageMessage, error: true),
  if (state._busy)
    const LinearProgressIndicator(
      semanticsLabel: 'Checking assisted SMS controls',
    ),
  _heading(context, 'SMS access'),
  if (state._loadError != null) _Message(state._loadError!, error: true),
  if (state._busy && state._access == null)
    const AdminLoadingState(title: 'Checking current Owner access'),
  if (state._access case final access?) ...[
    AdminRecordFactsTable(
      semanticLabel: 'Actual current assisted SMS grants',
      fields: [
        ('Current access decision revision', '${access.decisionRevision}'),
        (
          'View assisted SMS jobs',
          access.readGranted ? 'Granted' : 'Not granted',
        ),
        (
          'Review and record assisted SMS operations',
          access.manageGranted ? 'Granted' : 'Not granted',
        ),
      ],
    ),
    _ContextDetails(
      key: const Key('notification-management-access-details'),
      title: 'Account access details',
      semanticLabel: 'Current account access technical details',
      fields: [
        ('Owner account ID', access.adminId),
        ('Canonical principal ID', access.principalId),
        ('Existing Team access permission', 'admin_users.manage'),
        ('View jobs permission', 'assisted_sms.read'),
        ('Review operations permission', 'assisted_sms.manage'),
        ('Both operational grants present', access.canOperate ? 'Yes' : 'No'),
        (
          'Role capability definitions',
          'Role capability definitions set the maximum. The actual current account grants above determine access.',
        ),
        (
          'Sending approval',
          'Account grants and saved decisions do not establish legal release, provider approval or delivery.',
        ),
        ('Sender availability', 'No sender has been admitted.'),
      ],
    ),
    if (!access.canOperate)
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: state._accessConfirmed,
        onChanged: state._canWrite ? state._confirmAccess : null,
        title: const Text(
          'Allow my account to view jobs and manage assisted SMS.',
        ),
        subtitle: const Text(
          'View assisted SMS jobs; review and record assisted SMS operations.',
        ),
      ),
    Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed:
              state._canWrite && !access.canOperate && state._accessConfirmed
              ? () => state._setAccess(true)
              : null,
          icon: const Icon(Icons.verified_user_outlined),
          label: const Text('Enable access'),
        ),
        OutlinedButton.icon(
          onPressed:
              state._canWrite && (access.readGranted || access.manageGranted)
              ? () => state._setAccess(false)
              : null,
          icon: const Icon(Icons.remove_moderator_outlined),
          label: const Text('Remove access'),
        ),
      ],
    ),
  ],
  const _Message(
    'Sending is unavailable. Sender and release approvals are still required.',
  ),
];

const _secondaryDecisionLabels = {
  'Recorded state only',
  'Grant transaction ID',
  'Decision SHA-256',
};

List<(String, String)> _primaryDecisionFacts(List<(String, String)> fields) =>
    fields
        .where((field) => !_secondaryDecisionLabels.contains(field.$1))
        .toList();

List<(String, String)> _secondaryDecisionFacts(List<(String, String)> fields) =>
    fields
        .where((field) => _secondaryDecisionLabels.contains(field.$1))
        .toList();

class _ContextDetails extends StatelessWidget {
  const _ContextDetails({
    required this.title,
    required this.semanticLabel,
    required this.fields,
    super.key,
  });
  final String title, semanticLabel;
  final List<(String, String)> fields;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    expansionAnimationStyle: CollectMotion.animationStyle(context),
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(bottom: 12),
    leading: const Icon(Icons.info_outline),
    title: Text(title, semanticsLabel: semanticLabel),
    children: [
      AdminRecordFactsTable(semanticLabel: semanticLabel, fields: fields),
    ],
  );
}

Widget _heading(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(top: 24, bottom: 12),
  child: Semantics(
    header: true,
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  ),
);
AdminTableRowData _row(String id, Map<String, dynamic> fields) =>
    AdminTableRowData(
      id: id,
      title: id,
      subtitle: '',
      status: '',
      amount: '',
      extra: fields,
    );
AdminTableColumn _column(String key, String label) => AdminTableColumn(
  label: label,
  selectable: true,
  value: (row) => '${row.extra[key] ?? '—'}',
);
String _error(Object error) => error is AdminAccountException
    ? error.message
    : error is FormatException
    ? 'The response could not be verified. Keep the original UUID for reconciliation.'
    : 'The result could not be confirmed. Check the original request before another change.';

class _Message extends StatelessWidget {
  const _Message(this.message, {this.error = false});
  final String message;
  final bool error;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: error ? Theme.of(context).colorScheme.error : null,
        ),
      ),
    ),
  );
}
