part of 'admin_runtime.dart';

Future<void> allocateAdminExistingMember(
  BuildContext context,
  WidgetRef ref,
  AdminTableRowData row,
  VoidCallback onDone,
) async {
  final scope = _AdminActionScope(ref);
  if (!scope.isCurrent ||
      !(scope.permissions.contains('payments.allocate') ||
          scope.permissions.contains('payments.propose')) ||
      !scope.permissions.contains('users.read')) {
    return;
  }
  final eventId = row.extra['event_id'];
  if (row.extra['rail'] != 'rw_momo' ||
      eventId is! String ||
      !_reconciliationUuid.hasMatch(eventId)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Refresh this transaction before selecting a member.'),
      ),
    );
    return;
  }
  final receipt = await showDialog<AdminMemberAllocationReceipt>(
    context: context,
    barrierDismissible: false,
    animationStyle: CollectMotion.animationStyle(context),
    builder: (_) => _AdminSessionDialog(
      scope: scope,
      child: AdminMemberAllocationDialog(
        api: scope.repository.existingMemberAllocation,
        eventId: eventId,
        transactionLabel: '${row.title} · ${row.amount}',
        isCurrent: () => scope.isCurrent,
      ),
    ),
  );
  if (!context.mounted || !scope.isCurrent) return;
  // Even an unconfirmed response requires an authoritative queue refresh.
  onDone();
  if (receipt == null || !context.mounted || !scope.isCurrent) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(receipt.message)));
}
