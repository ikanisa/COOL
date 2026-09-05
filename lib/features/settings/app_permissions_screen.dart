import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;

import '../../core/notifications/collect_notification_service.dart';
import '../../core/security/sms_access_channel.dart';
import '../status/native_permission_sheets.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/providers/collect_app_state.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class AppPermissionsScreen extends ConsumerStatefulWidget {
  const AppPermissionsScreen({super.key});

  @override
  ConsumerState<AppPermissionsScreen> createState() =>
      _AppPermissionsScreenState();
}

class _AppPermissionsScreenState extends ConsumerState<AppPermissionsScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _notificationsEnabled = false;
  SmsAccessStatus _momoSmsStatus = const SmsAccessStatus.unavailable();
  permissions.PermissionStatus _cameraStatus =
      permissions.PermissionStatus.denied;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  @override
  Widget build(BuildContext context) {
    final receiverMode = ref.watch(momoReceiptCaptureAvailableProvider);
    return ScreenScaffold(
      title: 'App permissions',
      compact: true,
      onRefresh: _refresh,
      children: [
        CollectCard(
          emphasis: CollectCardEmphasis.normal,
          padding: const EdgeInsets.all(CollectSpacing.x4),
          child: Column(
            children: [
              if (receiverMode)
                _PermissionCard(
                  icon: CollectIcons.shield,
                  title: 'MoMo receipt SMS',
                  status: _loading
                      ? 'Checking'
                      : _momoSmsStatus.enabled
                      ? 'Allowed'
                      : 'Not allowed',
                  actionLabel: _momoSmsStatus.enabled
                      ? 'Turn off'
                      : _momoSmsStatus.permanentlyDenied
                      ? 'Phone settings'
                      : 'Review and allow',
                  onAction: _loading
                      ? null
                      : _momoSmsStatus.enabled
                      ? _disableMomoSms
                      : _momoSmsStatus.permanentlyDenied
                      ? const SmsAccessChannel().openAppSettings
                      : _requestMomoSms,
                ),
              _PermissionCard(
                icon: CollectIcons.pending,
                title: 'Notifications',
                status: _loading
                    ? 'Checking'
                    : _notificationsEnabled
                    ? 'Allowed'
                    : 'Not allowed',
                actionLabel: _notificationsEnabled ? 'Phone settings' : 'Allow',
                onAction: _loading
                    ? null
                    : _notificationsEnabled
                    ? permissions.openAppSettings
                    : _requestNotifications,
              ),
              _PermissionCard(
                icon: CollectIcons.qr,
                title: 'Camera',
                status: _loading
                    ? 'Checking'
                    : _cameraStatus.isGranted
                    ? 'Allowed'
                    : 'Not allowed',
                actionLabel:
                    _cameraStatus.isGranted || _cameraStatus.isPermanentlyDenied
                    ? 'Phone settings'
                    : 'Allow',
                onAction: _loading
                    ? null
                    : _cameraStatus.isGranted ||
                          _cameraStatus.isPermanentlyDenied
                    ? permissions.openAppSettings
                    : _requestCamera,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _loading = true);
    final service = ref.read(collectNotificationServiceProvider);
    final receiverMode = ref.read(momoReceiptCaptureAvailableProvider);
    final results = await Future.wait<Object>([
      service.areNotificationsEnabled(),
      permissions.Permission.camera.status,
      if (receiverMode)
        ref.read(collectRepositoryProvider.notifier).refreshSmsAccessStatus(),
    ]);
    if (!mounted) return;
    setState(() {
      _notificationsEnabled = results[0] as bool;
      _cameraStatus = results[1] as permissions.PermissionStatus;
      _momoSmsStatus = receiverMode
          ? results[2] as SmsAccessStatus
          : const SmsAccessStatus.unavailable();
      _loading = false;
    });
  }

  Future<void> _requestNotifications() async {
    final service = ref.read(collectNotificationServiceProvider);
    final granted = await service.requestPermission();
    if (granted) {
      unawaited(
        service.registerDevice(ref.read(collectRepositoryProvider.notifier)),
      );
    }
    await _refresh();
  }

  Future<void> _requestCamera() async {
    await permissions.Permission.camera.request();
    await _refresh();
  }

  Future<void> _requestMomoSms() async {
    if (!ref.read(momoReceiptCaptureAvailableProvider)) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: context.collectColors.transparent,
      barrierColor: CollectColors.publicBlack.withValues(alpha: 0.64),
      sheetAnimationStyle: CollectMotion.animationStyle(context),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          CollectSpacing.x4,
          CollectSpacing.x2,
          CollectSpacing.x4,
          MediaQuery.viewInsetsOf(sheetContext).bottom + CollectSpacing.x4,
        ),
        child: SingleChildScrollView(
          child: CollectBottomSheet(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CollectPermissionEducationSheet(
                  icon: CollectIcons.sms,
                  title: 'Allow MoMo receipt SMS access?',
                  message: 'Only new Rwanda MoMo receipt messages.',
                  education:
                      'Collect does not read inbox history or unrelated SMS. '
                      'New likely MoMo receipts are encrypted on this device, '
                      'bound to your signed-in account, and sent for secure '
                      'parsing and reconciliation.',
                  tone: CollectStatusTone.warning,
                ),
                CollectSpacing.gap16,
                CollectButton(
                  label: 'Continue',
                  icon: CollectIcons.shield,
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  expand: true,
                ),
                CollectButton(
                  label: 'Not now',
                  onPressed: () => Navigator.of(sheetContext).pop(false),
                  variant: CollectButtonVariant.secondary,
                  expand: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirmed != true ||
        !mounted ||
        !ref.read(momoReceiptCaptureAvailableProvider)) {
      return;
    }
    try {
      await ref.read(collectRepositoryProvider.notifier).setSmsAccess(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('MoMo receipt SMS access was not enabled.'),
          ),
        );
      }
    }
    await _refresh();
  }

  Future<void> _disableMomoSms() async {
    await ref.read(collectRepositoryProvider.notifier).setSmsAccess(false);
    await _refresh();
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.status,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String status;
  final String actionLabel;
  final FutureOr<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    final identity = Row(
      children: [
        Icon(icon, size: 22, color: context.collectColors.textSecondary),
        CollectSpacing.gapW12,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              CollectSpacing.gap4,
              Text(
                status,
                key: ValueKey('permission_status_$title'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.collectColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final action = TextButton(
      onPressed: onAction,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: context.collectColors.textPrimary,
      ),
      child: Text(actionLabel),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Preserve readable titles and touch targets when text is enlarged.
          final stacked =
              constraints.maxWidth < 330 ||
              MediaQuery.textScalerOf(context).scale(16) > 20;
          return stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    identity,
                    Align(alignment: Alignment.centerRight, child: action),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: identity),
                    CollectSpacing.gapW8,
                    action,
                  ],
                );
        },
      ),
    );
  }
}
