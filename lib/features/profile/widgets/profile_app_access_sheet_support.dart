part of 'profile_app_access_sheet.dart';

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(CoolRadii.pill),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        foregroundColor: colors.accent,
        backgroundColor: colors.chipSelectedBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CoolRadii.md),
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: colors.accent,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SmsPolicyNotice extends StatelessWidget {
  const _SmsPolicyNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong,
        borderRadius: BorderRadius.circular(CoolRadii.xl),
        boxShadow: CoolShadows.ambientFloat(strength: 0.15),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colors.inputSurface,
              borderRadius: BorderRadius.circular(CoolRadii.md),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.sms_outlined,
              color: colors.secondaryText,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.profileSmsSyncOptIn,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: CoolSpace.x1),
                Text(
                  context.l10n.profileSmsSyncOptInMessage,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.tertiaryText,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionMetadata {
  const _PermissionMetadata({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.linkedFeatures,
    required this.serviceActionLabel,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> linkedFeatures;
  final String serviceActionLabel;
}

_PermissionMetadata _metadataFor(
  BuildContext context,
  AppAccessPermission permission,
) {
  final l10n = context.l10n;
  return switch (permission) {
    AppAccessPermission.sms => _PermissionMetadata(
      icon: Icons.sms_outlined,
      title: l10n.profileSmsPaymentSyncTitle,
      subtitle: l10n.profileSmsPaymentSyncSubtitle,
      linkedFeatures: [
        l10n.profileAccessFeature12MonthImport,
        l10n.profileAccessFeatureMomoVerification,
      ],
      serviceActionLabel: l10n.openSystemSettings,
    ),
    AppAccessPermission.camera => _PermissionMetadata(
      icon: Icons.camera_alt_outlined,
      title: l10n.camera,
      subtitle: l10n.profileCameraSubtitle,
      linkedFeatures: [l10n.profileAccessFeatureMomoQrScan],
      serviceActionLabel: l10n.openSystemSettings,
    ),
    AppAccessPermission.contacts => _PermissionMetadata(
      icon: Icons.contacts_outlined,
      title: l10n.contacts,
      subtitle: l10n.profileContactsSubtitle,
      linkedFeatures: [
        l10n.profileAccessFeatureGroupInvites,
        l10n.profileAccessFeatureShareViaContacts,
      ],
      serviceActionLabel: l10n.openSystemSettings,
    ),
    AppAccessPermission.nfc => _PermissionMetadata(
      icon: Icons.nfc_outlined,
      title: l10n.nfc,
      subtitle: l10n.profileNfcSubtitle,
      linkedFeatures: [
        l10n.profileAccessFeatureMomoReceiveTap,
        l10n.profileAccessFeatureNfcPaymentTags,
      ],
      serviceActionLabel: l10n.profileOpenNfcSettings,
    ),
    AppAccessPermission.photos => _PermissionMetadata(
      icon: Icons.photo_library_outlined,
      title: l10n.profilePhotosMediaTitle,
      subtitle: l10n.profilePhotosMediaSubtitle,
      linkedFeatures: [
        l10n.profileAccessFeatureProfilePhoto,
        l10n.profileAccessFeatureDocumentUpload,
      ],
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

String _helperText(BuildContext context, AppAccessSnapshot snapshot) {
  return switch (snapshot.kind) {
    AppAccessStateKind.ready => context.l10n.ready,
    AppAccessStateKind.disabledInApp => context.l10n.offInCool,
    AppAccessStateKind.needsSystemPermission => context.l10n.needsAndroidAccess,
    AppAccessStateKind.blockedInSystem => context.l10n.blockedInSystem,
    AppAccessStateKind.serviceDisabled => context.l10n.profileServiceOff,
    AppAccessStateKind.notAvailable => context.l10n.notAvailable,
  };
}
