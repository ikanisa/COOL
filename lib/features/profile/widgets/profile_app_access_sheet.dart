import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/providers/app_access_provider.dart';
import '../../../core/providers/notification_settings_provider.dart';
import '../../../core/providers/app_lifecycle_providers.dart';
import '../../../core/services/fcm_service.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../core/services/app_access_service.dart';
import '../../../shared/widgets/cool_toast.dart';
import 'profile_settings_widgets.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';

part 'profile_app_access_sheet_cards.dart';
part 'profile_app_access_sheet_support.dart';

class ProfileAppAccessSheet extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

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
          child: const ProfileAppAccessPanel(),
        ),
      ),
    );
  }
}

class ProfileAppAccessPanel extends ConsumerStatefulWidget {
  const ProfileAppAccessPanel({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<ProfileAppAccessPanel> createState() =>
      _ProfileAppAccessPanelState();
}

class _ProfileAppAccessPanelState extends ConsumerState<ProfileAppAccessPanel>
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
        case AppAccessPermission.contacts:
        case AppAccessPermission.camera:
        case AppAccessPermission.location:
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

  Widget _buildAccessList(NotificationSettingsState notificationSettings) {
    return Column(
      children: [
        _NotificationAccessCard(
          settings: notificationSettings,
          onChanged: _toggleNotifications,
          onOpenSettings: _openNotificationSettings,
        ),
        const SizedBox(height: CoolSpace.x3),
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
              onChanged: (enabled) => _togglePermission(permission, enabled),
              onOpenSettings: () => _openSettings(permission),
            ),
            if (permission != _permissions.last)
              const SizedBox(height: CoolSpace.x3),
          ],
        const SizedBox(height: CoolSpace.x3),
        const _SmsPolicyNotice(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notificationSettings = ref.watch(notificationSettingsProvider);
    final readyCount =
        _snapshots.values.where((snapshot) => snapshot.isReady).length +
        (notificationSettings.status.isAuthorized &&
                notificationSettings.status.preferenceEnabled
            ? 1
            : 0);
    final totalCount = _permissions.length + 1;
    final listContent = _buildAccessList(notificationSettings);

    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryBanner(readyCount: readyCount, totalCount: totalCount),
          const SizedBox(height: CoolSpace.x4),
          listContent,
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.coolSemanticColors.borderStrong,
              borderRadius: BorderRadius.circular(CoolRadii.pill),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'App access',
          style: theme.textTheme.headlineSmall?.copyWith(
            color: context.coolSemanticColors.primaryText,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: CoolSpace.x2),
        Text(
          'Toggle feature access',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: context.coolSemanticColors.secondaryText,
            fontWeight: FontWeight.w400,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 14),
        _SummaryBanner(readyCount: readyCount, totalCount: totalCount),
        const SizedBox(height: CoolSpace.x4),
        Flexible(child: SingleChildScrollView(child: listContent)),
      ],
    );
  }
}
