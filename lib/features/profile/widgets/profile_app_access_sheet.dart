import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/providers/app_access_provider.dart';
import '../../../core/providers/notification_settings_provider.dart';
import '../../../core/providers/app_lifecycle_providers.dart';
import '../../mobility/providers/mobility_location_provider.dart';
import '../../../core/services/fcm_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../core/services/app_access_service.dart';
import '../../../shared/widgets/cool_toast.dart';
import 'profile_settings_widgets.dart';

class ProfileAppAccessSheet extends ConsumerStatefulWidget {
  const ProfileAppAccessSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
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
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                    color: AppColors.border2,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'App access',
                style: GoogleFonts.dmSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Toggle feature access',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.text2,
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.accentGlow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.admin_panel_settings_outlined,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$readyCount/$totalCount ready',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'All access controls',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppColors.text2,
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
    final isBlockedInSystem =
        settings.status.authorizationStatus == FcmAuthorizationStatus.denied;
    final statusLabel = settings.status.preferenceEnabled
        ? (settings.status.isAuthorized ? 'Ready' : 'Needs system access')
        : (isBlockedInSystem ? 'Blocked in system' : 'Off in COOL');
    final statusColor =
        settings.status.preferenceEnabled && settings.status.isAuthorized
        ? AppColors.accent
        : isBlockedInSystem
        ? AppColors.red
        : settings.status.preferenceEnabled
        ? AppColors.orange
        : AppColors.text2;
    final canOpenSettings = isBlockedInSystem;

    return _AccessCardShell(
      icon: Icons.notifications_outlined,
      title: 'Notifications',
      subtitle: 'Payment and activity alerts',
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
              label: 'Open system settings',
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
    final status = _statusFor(snapshot);
    final footerAction = switch (snapshot.kind) {
      AppAccessStateKind.blockedInSystem => _InlineActionButton(
        label: 'Open system settings',
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
              activeTrackColor: AppColors.accent,
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
        final isNarrow = constraints.maxWidth < 380;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
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
                      color: AppColors.surface3,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, color: AppColors.text, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isNarrow) ...[
                          Text(
                            title,
                            style: GoogleFonts.dmSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
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
                                  style: GoogleFonts.dmSans(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.text,
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
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: AppColors.text2,
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
                          color: AppColors.surface3,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          feature,
                          style: GoogleFonts.dmSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text2,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              Text(
                helperText,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: AppColors.text3,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
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
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.accentGlow,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _SmsPolicyNotice extends StatelessWidget {
  const _SmsPolicyNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.surface3,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.sms_outlined, color: AppColors.text2, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SMS sync opt-in',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'If you turn this on, Cool will read only M-Money '
                  'confirmation SMS to verify your payments. '
                  'Matched messages are sent to our server for '
                  'AI-powered transaction parsing. No personal '
                  'messages are accessed or stored.',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppColors.text3,
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
      title: 'SMS payment sync',
      subtitle:
          'Optional on Android so Cool can auto-verify '
          'M-Money payments and reconcile group contributions, '
          'subscriptions, and partner transactions.',
      linkedFeatures: ['MoMo verification', 'Transaction recording'],
      serviceActionLabel: 'Open system settings',
    ),
    AppAccessPermission.location => const _PermissionMetadata(
      icon: Icons.location_on_outlined,
      title: 'Location',
      subtitle:
          'Needed for nearby mobility',
      linkedFeatures: ['Mobility nearby', 'Trip pickup', 'Driver discovery'],
      serviceActionLabel: 'Open location settings',
    ),
    AppAccessPermission.camera => const _PermissionMetadata(
      icon: Icons.camera_alt_outlined,
      title: 'Camera',
      subtitle:
          'Used for MoMo QR',
      linkedFeatures: ['MoMo QR scan', 'Ticket scan'],
      serviceActionLabel: 'Open system settings',
    ),
    AppAccessPermission.contacts => const _PermissionMetadata(
      icon: Icons.contacts_outlined,
      title: 'Contacts',
      subtitle:
          'Used when inviting group',
      linkedFeatures: ['Group invites', 'Share via contacts'],
      serviceActionLabel: 'Open system settings',
    ),
    AppAccessPermission.nfc => const _PermissionMetadata(
      icon: Icons.nfc_outlined,
      title: 'NFC',
      subtitle:
          'Controls NFC receive/read flows',
      linkedFeatures: ['MoMo receive tap', 'NFC payment tags'],
      serviceActionLabel: 'Open NFC settings',
    ),
  };
}

({String label, Color color}) _statusFor(AppAccessSnapshot snapshot) {
  return switch (snapshot.kind) {
    AppAccessStateKind.ready => (label: 'Ready', color: AppColors.accent),
    AppAccessStateKind.disabledInApp => (
      label: 'Off in COOL',
      color: AppColors.text2,
    ),
    AppAccessStateKind.needsSystemPermission => (
      label: 'Needs Android access',
      color: AppColors.orange,
    ),
    AppAccessStateKind.blockedInSystem => (
      label: 'Blocked in system',
      color: AppColors.red,
    ),
    AppAccessStateKind.serviceDisabled => (
      label: 'Device setting off',
      color: AppColors.orange,
    ),
    AppAccessStateKind.notAvailable => (
      label: 'Not available',
      color: AppColors.text3,
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
