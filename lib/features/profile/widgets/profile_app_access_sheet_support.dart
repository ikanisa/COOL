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
                  'SMS sync opt-in',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: CoolSpace.x1),
                Text(
                  'Android only. COOL checks approved M-Money sender IDs, imports matching confirmations, and ignores other SMS.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.tertiaryText,
                    fontWeight: FontWeight.w600,
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

_PermissionMetadata _metadataFor(AppAccessPermission permission) {
  return switch (permission) {
    AppAccessPermission.sms => const _PermissionMetadata(
      icon: Icons.sms_outlined,
      title: 'SMS Payment Sync',
      subtitle:
          'Optional on Android. Watches approved M-Money sender IDs, '
          'imports matching confirmations, and auto-verifies supported '
          'payment flows.',
      linkedFeatures: ['12-month import', 'MoMo verification'],
      serviceActionLabel: 'Open system settings',
    ),
    AppAccessPermission.location => const _PermissionMetadata(
      icon: Icons.location_on_outlined,
      title: 'Location',
      subtitle: 'Used for nearby services and place-aware flows',
      linkedFeatures: ['Nearby services', 'Partner discovery', 'Map context'],
      serviceActionLabel: 'Open location settings',
    ),
    AppAccessPermission.camera => const _PermissionMetadata(
      icon: Icons.camera_alt_outlined,
      title: 'Camera',
      subtitle: 'Used for MoMo QR',
      linkedFeatures: ['MoMo QR scan'],
      serviceActionLabel: 'Open system settings',
    ),
    AppAccessPermission.contacts => const _PermissionMetadata(
      icon: Icons.contacts_outlined,
      title: 'Contacts',
      subtitle: 'Used when inviting group',
      linkedFeatures: ['Group invites', 'Share via contacts'],
      serviceActionLabel: 'Open system settings',
    ),
    AppAccessPermission.nfc => const _PermissionMetadata(
      icon: Icons.nfc_outlined,
      title: 'NFC',
      subtitle: 'Controls NFC receive/read flows',
      linkedFeatures: ['MoMo receive tap', 'NFC payment tags'],
      serviceActionLabel: 'Open NFC settings',
    ),
    AppAccessPermission.photos => const _PermissionMetadata(
      icon: Icons.photo_library_outlined,
      title: 'Photos & Media',
      subtitle: 'Choose profile photos and upload documents from gallery.',
      linkedFeatures: ['Profile photo', 'Document upload'],
      serviceActionLabel: 'Open system settings',
    ),
  };
}

({String label, Color color}) _statusFor(
  BuildContext context,
  AppAccessSnapshot snapshot,
) {
  final colors = context.coolSemanticColors;
  return switch (snapshot.kind) {
    AppAccessStateKind.ready => (label: 'Ready', color: colors.accent),
    AppAccessStateKind.disabledInApp => (
      label: 'Off in COOL',
      color: colors.secondaryText,
    ),
    AppAccessStateKind.needsSystemPermission => (
      label: 'Needs Android access',
      color: colors.warning,
    ),
    AppAccessStateKind.blockedInSystem => (
      label: 'Blocked in system',
      color: colors.danger,
    ),
    AppAccessStateKind.serviceDisabled => (
      label: 'Device setting off',
      color: colors.warning,
    ),
    AppAccessStateKind.notAvailable => (
      label: 'Not available',
      color: colors.tertiaryText,
    ),
  };
}

String _helperText(AppAccessSnapshot snapshot) {
  return switch (snapshot.kind) {
    AppAccessStateKind.ready => 'Ready',
    AppAccessStateKind.disabledInApp => 'Off in COOL',
    AppAccessStateKind.needsSystemPermission => 'Needs Android access',
    AppAccessStateKind.blockedInSystem => 'Blocked in system',
    AppAccessStateKind.serviceDisabled => 'Service off',
    AppAccessStateKind.notAvailable => 'Not available',
  };
}
