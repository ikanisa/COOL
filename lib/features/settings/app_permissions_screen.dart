import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;

import '../../core/notifications/collect_notification_service.dart';
import '../../core/security/sms_access_channel.dart';
import '../../app/env/app_env.dart';
import '../../shared/repositories/collect_repository.dart';
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
  SmsAccessStatus _bankSmsStatus = const SmsAccessStatus.unavailable();
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
    final receiverMode = ref.watch(appEnvProvider).enableAndroidSmsAccess;
    return ScreenScaffold(
      title: 'App permissions',
      subtitle: 'Control only the device access Collect needs.',
      compact: true,
      onRefresh: _refresh,
      children: [
        InfoSecurityBanner(
          title: receiverMode
              ? 'Controlled bank-evidence receiver'
              : 'No payment or SMS permission',
          message: receiverMode
              ? 'This separately signed operations build can capture new beneficiary-bank notification SMS. Messages are candidate evidence only and never confirm a contribution without daily statement reconciliation.'
              : 'Bank transfers are completed in your banking app. Collect does not request SMS, phone, contacts, card, or bank-account access from members.',
          tone: CollectStatusTone.privacy,
        ),
        if (receiverMode)
          _PermissionCard(
            icon: CollectIcons.shield,
            title: 'Bank notification SMS',
            explanation:
                'Capture only new incoming EUR bank-transfer notifications on this controlled operations device.',
            status: _loading
                ? 'Checking'
                : _bankSmsStatus.enabled
                ? 'Allowed'
                : 'Not allowed',
            tone: _bankSmsStatus.enabled
                ? CollectStatusTone.success
                : CollectStatusTone.warning,
            actionLabel: _bankSmsStatus.enabled ? 'Phone settings' : 'Allow',
            onAction: _loading
                ? null
                : _bankSmsStatus.enabled || _bankSmsStatus.permanentlyDenied
                ? const SmsAccessChannel().openAppSettings
                : _requestBankSms,
          ),
        _PermissionCard(
          icon: CollectIcons.pending,
          title: 'Notifications',
          explanation:
              'Reconciliation confirmations, contribution reminders, group updates, and security notices.',
          status: _loading
              ? 'Checking'
              : _notificationsEnabled
              ? 'Allowed'
              : 'Not allowed',
          tone: _notificationsEnabled
              ? CollectStatusTone.success
              : CollectStatusTone.warning,
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
          explanation:
              'Scan a group QR code. Collect does not need gallery access for scanning.',
          status: _loading
              ? 'Checking'
              : _cameraStatus.isGranted
              ? 'Allowed'
              : 'Not allowed',
          tone: _cameraStatus.isGranted
              ? CollectStatusTone.success
              : CollectStatusTone.warning,
          actionLabel:
              _cameraStatus.isGranted || _cameraStatus.isPermanentlyDenied
              ? 'Phone settings'
              : 'Allow',
          onAction: _loading
              ? null
              : _cameraStatus.isGranted || _cameraStatus.isPermanentlyDenied
              ? permissions.openAppSettings
              : _requestCamera,
        ),
      ],
    );
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _loading = true);
    final service = ref.read(collectNotificationServiceProvider);
    final receiverMode = ref.read(appEnvProvider).enableAndroidSmsAccess;
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
      _bankSmsStatus = receiverMode
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

  Future<void> _requestBankSms() async {
    await ref.read(collectRepositoryProvider.notifier).setSmsAccess(true);
    await _refresh();
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.explanation,
    required this.status,
    required this.tone,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String explanation;
  final String status;
  final CollectStatusTone tone;
  final String actionLabel;
  final FutureOr<void> Function()? onAction;

  @override
  Widget build(BuildContext context) => CollectCard(
    emphasis: CollectCardEmphasis.normal,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon),
            CollectSpacing.gapW12,
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(status, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
        CollectSpacing.gap12,
        Text(explanation),
        CollectSpacing.gap16,
        CollectButton(
          label: actionLabel,
          onPressed: onAction,
          variant: CollectButtonVariant.secondary,
          expand: true,
        ),
      ],
    ),
  );
}
