part of 'profile_app_access_sheet.dart';

class _InlineActionButton extends StatelessWidget {
  const _InlineActionButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, CoolTapTargets.minimum),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        foregroundColor: colors.accent,
        backgroundColor: colors.chipSelectedBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CoolRadii.md),
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: colors.accent,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PermissionMetadata {
  const _PermissionMetadata({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.serviceActionLabel,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String serviceActionLabel;
}

_PermissionMetadata _metadataFor(
  BuildContext context,
  AppAccessPermission permission,
) {
  final l10n = context.l10n;
  return switch (permission) {
    AppAccessPermission.sms => _PermissionMetadata(
      icon: CoolIcons.sms,
      title: l10n.profileSmsPaymentSyncTitle,
      subtitle: l10n.profileSmsPaymentSyncSubtitle,
      serviceActionLabel: l10n.openSystemSettings,
    ),
    AppAccessPermission.camera => _PermissionMetadata(
      icon: CoolIcons.camera,
      title: l10n.camera,
      subtitle: l10n.profileCameraSubtitle,
      serviceActionLabel: l10n.openSystemSettings,
    ),
    AppAccessPermission.contacts => _PermissionMetadata(
      icon: CoolIcons.contacts,
      title: l10n.contacts,
      subtitle: l10n.profileContactsSubtitle,
      serviceActionLabel: l10n.openSystemSettings,
    ),
    AppAccessPermission.nfc => _PermissionMetadata(
      icon: CoolIcons.nfc,
      title: l10n.nfc,
      subtitle: l10n.profileNfcSubtitle,
      serviceActionLabel: l10n.profileOpenNfcSettings,
    ),
    AppAccessPermission.photos => _PermissionMetadata(
      icon: CoolIcons.photos,
      title: l10n.profilePhotosMediaTitle,
      subtitle: l10n.profilePhotosMediaSubtitle,
      serviceActionLabel: l10n.openSystemSettings,
    ),
  };
}

({String label, Color color}) _statusFor(
  BuildContext context,
  AppAccessSnapshot snapshot,
) {
  final colors = context.coolSemanticColors;
  return switch (snapshot.kind) {
    AppAccessStateKind.ready => (
      label: context.l10n.ready,
      color: colors.accent,
    ),
    AppAccessStateKind.disabledInApp => (
      label: context.l10n.offInCool,
      color: colors.secondaryText,
    ),
    AppAccessStateKind.needsSystemPermission => (
      label: context.l10n.needsAndroidAccess,
      color: colors.warning,
    ),
    AppAccessStateKind.blockedInSystem => (
      label: context.l10n.blockedInSystem,
      color: colors.danger,
    ),
    AppAccessStateKind.serviceDisabled => (
      label: context.l10n.deviceSettingOff,
      color: colors.warning,
    ),
    AppAccessStateKind.notAvailable => (
      label: context.l10n.notAvailable,
      color: colors.tertiaryText,
    ),
  };
}
