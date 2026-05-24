class AdminPermissionSet {
  const AdminPermissionSet(this.permissions);

  final Set<String> permissions;

  bool allows(String permission) => permissions.contains(permission);
}
