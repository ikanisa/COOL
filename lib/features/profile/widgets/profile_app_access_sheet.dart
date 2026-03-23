import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/providers/app_access_provider.dart';
import '../../../core/providers/notification_settings_provider.dart';
import '../../../core/providers/app_lifecycle_providers.dart';
import '../../mobility/providers/mobility_location_provider.dart';
import '../../../core/services/fcm_service.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../core/services/app_access_service.dart';
import '../../../shared/widgets/cool_toast.dart';
import 'profile_settings_widgets.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';

class ProfileAppAccessSheet extends ConsumerStatefulWidget {
  const ProfileAppAccessSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showCoolBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const ProfileAppAccessSheet(),
    );
  }

  @override
  ConsumerState<ProfileAppAccessSheet> createState() =>
      _ProfileAppAccessSheetState();
}

class _ProfileAppAccessSheetState extends ConsumerState<ProfileAppAccessSheet>
    with WidgetsBindingObserver {
  static const _permissions = <AppAccessPermission>[
    AppAccessPermission.sms,
    AppAccessPermission.location,
    AppAccessPermission.camera,
    AppAccessPermission.contacts,
    AppAccessPermission.photos,
    AppAccessPermission.nfc,
  ];

  late final AppAccessService _service = ref.read(appAccessServiceProvider);
  final _busy = <AppAccessPermission>{};
  final _snapshots = <AppAccessPermission, AppAccessSnapshot>{};

  bool _isLoading = true;
  bool _refreshOnResume = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service.changes.addListener(_handleAccessServiceChange);
    _loadSnapshots();
  }

  @override
  void dispose() {
    _service.changes.removeListener(_handleAccessServiceChange);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_refreshOnResume) {
      return;
    }
    _refreshOnResume = false;
    _loadSnapshots();
  }

  void _handleAccessServiceChange() {
    if (!mounted) {
      return;
    }
    _refreshSnapshotsSilently();
  }

  Future<void> _loadSnapshots() async {
    setState(() => _isLoading = true);
    final snapshots = await _service.getSnapshots(_permissions);
    if (!mounted) {
      return;
    }
    setState(() {
      _snapshots
        ..clear()
        ..addEntries(
          snapshots.map((snapshot) => MapEntry(snapshot.permission, snapshot)),
        );
      _isLoading = false;
    });
  }

  Future<void> _refreshSnapshotsSilently() async {
    final snapshots = await _service.getSnapshots(_permissions);
    if (!mounted) {
      return;
    }
    setState(() {
      _snapshots
        ..clear()
        ..addEntries(
          snapshots.map((snapshot) => MapEntry(snapshot.permission, snapshot)),
        );
    });
  }

  Future<void> _togglePermission(
    AppAccessPermission permission,
    bool enabled,
  ) async {
    setState(() => _busy.add(permission));
    final snapshot = enabled
        ? await _service.enableAndRequest(permission)
        : await _service.disable(permission);
    if (!mounted) {
      return;
    }
    setState(() {
      _snapshots[permission] = snapshot;
      _busy.remove(permission);
    });

    // Active teardown for features that keep running in the background.
    if (!enabled) {
      switch (permission) {
        case AppAccessPermission.sms:
          await ref.read(momoSmsAutoreadServiceProvider).stop();
          break;
        case AppAccessPermission.location:
          ref.read(mobilityLocationProvider.notifier).stopTracking();
          break;
        case AppAccessPermission.contacts:
        case AppAccessPermission.camera:
        case AppAccessPermission.nfc:
        case AppAccessPermission.photos:
          break;
      }
    }
    if (permission == AppAccessPermission.sms) {
      await ref.read(momoSmsAutoreadServiceProvider).refresh();
    }
  }

  Future<void> _openSettings(AppAccessPermission permission) async {
    setState(() => _busy.add(permission));
    _refreshOnResume = true;
    final opened = await _service.openSystemSettings(permission);
    if (!mounted) {
      return;
    }
    if (!opened) {
      _refreshOnResume = false;
    }
    setState(() => _busy.remove(permission));
    if (!opened) {
      CoolToast.error(context, 'Settings unavailable');
    }
  }

  Future<void> _openNotificationSettings() async {
    _refreshOnResume = true;
    final opened = await openAppSettings();
    if (!mounted) {
      return;
    }
    if (!opened) {
      _refreshOnResume = false;
      CoolToast.error(context, 'Settings unavailable');
    }
  }

  Future<void> _toggleNotifications(bool enabled) async {
    await ref.read(notificationSettingsProvider.notifier).setEnabled(enabled);
    if (!mounted) {
      return;
    }
    final error = ref.read(notificationSettingsProvider).error;
    if (error != null && error.isNotEmpty) {
      CoolToast.error(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final notificationSettings = ref.watch(notificationSettingsProvider);
    final readyCount =
        _snapshots.values.where((snapshot) => snapshot.isReady).length +
        (notificationSettings.status.isAuthorized &&
                notificationSettings.status.preferenceEnabled
            ? 1
            : 0);
    final totalCount = _permissions.length + 1;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.overlaySurface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(CoolRadii.xxl),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            12,
            18,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.borderStrong,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'App access',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Toggle feature access',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.secondaryText,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              _SummaryBanner(readyCount: readyCount, totalCount: totalCount),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _NotificationAccessCard(
                        settings: notificationSettings,
                        onChanged: _toggleNotifications,
                        onOpenSettings: _openNotificationSettings,
                      ),
                      const SizedBox(height: 12),
                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: CoolSkeletonList(itemCount: 3),
                        )
                      else
                        for (final permission in _permissions) ...[
                          _PermissionAccessCard(
                            metadata: _metadataFor(permission),
                            snapshot: _snapshots[permission]!,
                            isBusy: _busy.contains(permission),
                            onChanged: (enabled) =>
                                _togglePermission(permission, enabled),
                            onOpenSettings: () => _openSettings(permission),
                          ),
                          if (permission != _permissions.last)
                            const SizedBox(height: 12),
                        ],
                      const SizedBox(height: 12),
                      const _SmsPolicyNotice(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({required this.readyCount, required this.totalCount});

  final int readyCount;
  final int totalCount;

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
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colors.chipSelectedBackground,
              borderRadius: BorderRadius.circular(CoolRadii.md),
            ),
            child: Icon(
              Icons.admin_panel_settings_outlined,
              color: colors.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$readyCount/$totalCount ready',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'All access controls',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.secondaryText,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
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

class _NotificationAccessCard extends StatelessWidget {
  const _NotificationAccessCard({
    required this.settings,
    required this.onChanged,
    required this.onOpenSettings,
  });

  final NotificationSettingsState settings;
  final ValueChanged<bool> onChanged;
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final isBlockedInSystem =
        settings.status.authorizationStatus == FcmAuthorizationStatus.denied;
    final statusLabel = settings.status.preferenceEnabled
        ? (settings.status.isAuthorized ? 'Ready' : 'Needs system access')
        : (isBlockedInSystem ? 'Blocked in system' : 'Off in COOL');
    final statusColor =
        settings.status.preferenceEnabled && settings.status.isAuthorized
        ? colors.accent
        : isBlockedInSystem
        ? colors.danger
        : settings.status.preferenceEnabled
        ? colors.warning
        : colors.secondaryText;
    final canOpenSettings = isBlockedInSystem;

    return _AccessCardShell(
      icon: Icons.notifications_outlined,
      title: context.l10n.notifications,
      subtitle: context.l10n.paymentAndActivityAlerts,
      statusLabel: statusLabel,
      statusColor: statusColor,
      linkedFeatures: const [
        'MoMo updates',
        'Groups activity',
        'Mobility alerts',
        'Partner announcements',
      ],
      trailing: ProfileNotificationToggle(
        value: settings.status.preferenceEnabled,
        onChanged: onChanged,
        isLoading: settings.isLoading,
      ),
      footerAction: canOpenSettings
          ? _InlineActionButton(
              label: context.l10n.openSystemSettings,
              onTap: () => onOpenSettings(),
            )
          : null,
      helperText: isBlockedInSystem
          ? 'Blocked in system'
          : settings.status.preferenceEnabled
          ? 'Enabled'
          : 'Disabled',
    );
  }
}

class _PermissionAccessCard extends StatelessWidget {
  const _PermissionAccessCard({
    required this.metadata,
    required this.snapshot,
    required this.isBusy,
    required this.onChanged,
    required this.onOpenSettings,
  });

  final _PermissionMetadata metadata;
  final AppAccessSnapshot snapshot;
  final bool isBusy;
  final ValueChanged<bool> onChanged;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final status = _statusFor(context, snapshot);
    final footerAction = switch (snapshot.kind) {
      AppAccessStateKind.blockedInSystem => _InlineActionButton(
        label: context.l10n.openSystemSettings,
        onTap: onOpenSettings,
      ),
      AppAccessStateKind.serviceDisabled => _InlineActionButton(
        label: metadata.serviceActionLabel,
        onTap: onOpenSettings,
      ),
      AppAccessStateKind.notAvailable => null,
      _ => null,
    };

    return _AccessCardShell(
      icon: metadata.icon,
      title: metadata.title,
      subtitle: metadata.subtitle,
      statusLabel: status.label,
      statusColor: status.color,
      linkedFeatures: metadata.linkedFeatures,
      trailing: isBusy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CupertinoActivityIndicator(radius: 12),
            )
          : Switch.adaptive(
              value: snapshot.enabledInApp,
              onChanged: snapshot.kind == AppAccessStateKind.notAvailable
                  ? null
                  : onChanged,
              activeTrackColor: colors.accent,
            ),
      footerAction: footerAction,
      helperText: _helperText(snapshot, metadata),
    );
  }
}

class _AccessCardShell extends StatelessWidget {
  const _AccessCardShell({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.statusLabel,
    required this.statusColor,
    required this.linkedFeatures,
    required this.trailing,
    required this.helperText,
    this.footerAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String statusLabel;
  final Color statusColor;
  final List<String> linkedFeatures;
  final Widget trailing;
  final Widget? footerAction;
  final String helperText;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final colors = context.coolSemanticColors;
        final isNarrow = constraints.maxWidth < 380;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.cardSurfaceStrong,
            borderRadius: BorderRadius.circular(CoolRadii.xl),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.inputSurface,
                      borderRadius: BorderRadius.circular(CoolRadii.md),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, color: colors.primaryText, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isNarrow) ...[
                          Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: colors.primaryText,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _StatusPill(
                                label: statusLabel,
                                color: statusColor,
                              ),
                              trailing,
                            ],
                          ),
                        ] else
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: colors.primaryText,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _StatusPill(
                                label: statusLabel,
                                color: statusColor,
                              ),
                            ],
                          ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.secondaryText,
                            fontWeight: FontWeight.w600,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isNarrow) ...[const SizedBox(width: 12), trailing],
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: linkedFeatures
                    .map(
                      (feature) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colors.chipBackground,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: colors.border),
                        ),
                        child: Text(
                          feature,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.secondaryText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              Text(
                helperText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.tertiaryText,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                ),
              ),
              if (footerAction != null) ...[
                const SizedBox(height: 12),
                footerAction!,
              ],
            ],
          ),
        );
      },
    );
  }
}

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
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
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
        border: Border.all(color: colors.border),
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
                const SizedBox(height: 4),
                Text(
                  'Reads approved M-Money SMS only. A one-time import can backfill the last year.',
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
          'Optional on Android. Imports approved M-Money confirmations '
          'and auto-verifies supported payment flows.',
      linkedFeatures: ['12-month import', 'MoMo verification'],
      serviceActionLabel: 'Open system settings',
    ),
    AppAccessPermission.location => const _PermissionMetadata(
      icon: Icons.location_on_outlined,
      title: 'Location',
      subtitle: 'Needed for nearby mobility',
      linkedFeatures: ['Mobility nearby', 'Trip pickup', 'Driver discovery'],
      serviceActionLabel: 'Open location settings',
    ),
    AppAccessPermission.camera => const _PermissionMetadata(
      icon: Icons.camera_alt_outlined,
      title: 'Camera',
      subtitle: 'Used for MoMo QR',
      linkedFeatures: ['MoMo QR scan', 'Ticket scan'],
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

String _helperText(AppAccessSnapshot snapshot, _PermissionMetadata metadata) {
  return switch (snapshot.kind) {
    AppAccessStateKind.ready => 'Ready',
    AppAccessStateKind.disabledInApp => 'Off in COOL',
    AppAccessStateKind.needsSystemPermission => 'Needs Android access',
    AppAccessStateKind.blockedInSystem => 'Blocked in system',
    AppAccessStateKind.serviceDisabled => 'Service off',
    AppAccessStateKind.notAvailable => 'Not available',
  };
}
