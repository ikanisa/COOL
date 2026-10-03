part of 'admin_runtime.dart';

/// Navigation has an independent audit gate and never invokes an entity action.
class AdminEntityAuditLink extends ConsumerWidget {
  const AdminEntityAuditLink({
    required this.kind,
    required this.id,
    this.onOpenHistory,
    super.key,
  });
  final AdminAuditEntityKind kind;
  final String id;
  final VoidCallback? onOpenHistory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = _adminResolvedIdentity(ref.watch(adminIdentityProvider));
    final session = ref.watch(adminAuthSessionScopeProvider);
    if (session == null ||
        identity?.userId != session.key.userId ||
        !adminEntityAuditCanRead(identity, kind)) {
      return const SizedBox.shrink();
    }
    String path;
    try {
      path = adminEntityAuditPath(kind, id);
    } on FormatException {
      return const SizedBox.shrink();
    }
    return OutlinedButton.icon(
      key: ValueKey('entity-audit-link-${kind.wire}-$id'),
      onPressed: onOpenHistory ?? () => context.push(path),
      icon: const Icon(Icons.history),
      label: const Text('View action history'),
    );
  }
}
