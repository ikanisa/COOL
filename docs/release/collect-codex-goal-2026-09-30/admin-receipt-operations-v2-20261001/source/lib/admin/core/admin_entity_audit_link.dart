part of 'admin_runtime.dart';

/// Navigation has an independent audit gate and never invokes an entity action.
class AdminEntityAuditLink extends ConsumerWidget {
  const AdminEntityAuditLink({required this.kind, required this.id, super.key});
  final AdminAuditEntityKind kind;
  final String id;

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
      onPressed: () => context.push(path),
      icon: const Icon(Icons.history),
      label: const Text('View action history'),
    );
  }
}
