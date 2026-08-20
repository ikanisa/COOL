import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;

import '../../core/notifications/collect_notification_service.dart';
import '../../core/security/sms_access_channel.dart';
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
  final SmsAccessChannel _smsAccess = const SmsAccessChannel();
  bool _loading = true;
  bool _notificationsEnabled = false;
  permissions.PermissionStatus _cameraStatus =
      permissions.PermissionStatus.denied;
  SmsAccessStatus _smsStatus = const SmsAccessStatus.unavailable();
  String? _smsError;

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
    final repositoryState = ref.watch(collectRepositoryProvider);
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    return ScreenScaffold(
      title: 'App permissions',
      subtitle: 'Control only the device access Collect needs.',
      compact: true,
      onRefresh: _refresh,
      children: [
        const InfoSecurityBanner(
          title: 'You stay in control',
          message:
              'Collect asks at the moment a feature needs access. You can deny, disable, or review every permission in phone settings.',
          tone: CollectStatusTone.privacy,
        ),
        _PermissionCard(
          icon: CollectIcons.pending,
          title: 'Notifications',
          explanation:
              'Payment reminders, contribution confirmations, group updates, and security notices.',
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
              ? _openSystemSettings
              : _requestNotifications,
        ),
        _PermissionCard(
          icon: CollectIcons.qr,
          title: 'Camera',
          explanation:
              'Scan a group QR code. Collect does not need gallery or photo-library access for scanning.',
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
              ? _openSystemSettings
              : _requestCamera,
        ),
        if (isAndroid)
          _PermissionCard(
            icon: CollectIcons.sms,
            title: 'MoMo SMS access',
            explanation: _smsStatus.declared
                ? 'Read only new MTN or Airtel mobile-money transaction messages after you opt in. Inbox history and unrelated SMS are not read.'
                : 'This Android build does not include the restricted SMS receiver.',
            status: _loading
                ? 'Checking'
                : !_smsStatus.supported
                ? 'Unavailable'
                : _smsStatus.enabled
                ? 'Allowed and on'
                : _smsStatus.permanentlyDenied
                ? 'Blocked in settings'
                : 'Off',
            tone: _smsStatus.enabled
                ? CollectStatusTone.success
                : _smsStatus.supported
                ? CollectStatusTone.warning
                : CollectStatusTone.info,
            actionLabel: _smsStatus.enabled
                ? 'Turn off'
                : _smsStatus.permanentlyDenied
                ? 'Phone settings'
                : 'Review and allow',
            onAction: _loading || !_smsStatus.supported
                ? null
                : _smsStatus.enabled
                ? _disableSms
                : _smsStatus.permanentlyDenied
                ? _openSmsSettings
                : _reviewAndRequestSms,
          ),
        if (_smsStatus.queueOverflowed || repositoryState.smsQueueOverflowed)
          const InfoSecurityBanner(
            title: 'SMS queue needs attention',
            message:
                'The protected on-device queue reached capacity. Existing receipts were preserved; keep Collect open and contact support before relying on missing receipts.',
            tone: CollectStatusTone.warning,
          ),
        if (repositoryState.smsSyncNeedsAttention)
          const InfoSecurityBanner(
            title: 'A receipt is waiting to sync',
            message:
                'The protected receipt remains queued and will retry automatically. Keep Collect online and open this screen again if the warning continues.',
            tone: CollectStatusTone.warning,
          ),
        if (_smsError != null)
          InfoSecurityBanner(
            title: 'SMS access was not changed',
            message: _smsError!,
            tone: CollectStatusTone.warning,
          ),
        const InfoSecurityBanner(
          title: 'Restricted SMS permission',
          message:
              'Android SMS access is optional and consent-gated. New MoMo messages are encrypted while queued, uploaded when Collect opens or resumes, and parsed through the server-side OpenAI API. An exact match remains pending until independent provider confirmation; only then can it reach the ledger. Store distribution remains subject to Google Play approval.',
          tone: CollectStatusTone.warning,
        ),
      ],
    );
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _loading = true);
    final notificationService = ref.read(collectNotificationServiceProvider);
    final results = await Future.wait<Object>([
      notificationService.areNotificationsEnabled(),
      permissions.Permission.camera.status,
      _smsAccess.status(),
    ]);
    if (!mounted) return;
    setState(() {
      _notificationsEnabled = results[0] as bool;
      _cameraStatus = results[1] as permissions.PermissionStatus;
      _smsStatus = results[2] as SmsAccessStatus;
      _loading = false;
    });
  }

  Future<void> _requestNotifications() async {
    final service = ref.read(collectNotificationServiceProvider);
    final granted = await service.requestPermission();
    if (granted) {
      final repository = ref.read(collectRepositoryProvider.notifier);
      unawaited(service.registerDevice(repository));
      await service.showNotification(
        title: 'Collect notifications enabled',
        body: 'You can manage each notification category in phone settings.',
        payload: '/settings/notifications',
        eventType: 'security.permission_enabled',
      );
    }
    await _refresh();
  }

  Future<void> _requestCamera() async {
    await permissions.Permission.camera.request();
    await _refresh();
  }

  Future<void> _reviewAndRequestSms() async {
    final accepted =
        await showDialog<bool>(
          context: context,
          animationStyle: CollectMotion.animationStyle(context),
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(CollectIcons.sms),
            title: const Text('Allow MoMo SMS access?'),
            content: const Text(
              'Collect will capture only new MTN or Airtel mobile-money transaction messages after permission is granted. It does not read inbox history or unrelated SMS. Pending receipts are encrypted on this device and sent through Collect servers to the OpenAI API for structured parsing. They are deleted from the device queue only after durable ingestion and parsing. An exact match creates a review candidate; the contribution and balances post only after independent provider confirmation.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Continue'),
              ),
            ],
          ),
        ) ??
        false;
    if (!accepted || !mounted) return;
    try {
      await ref.read(collectRepositoryProvider.notifier).setSmsAccess(true);
      if (mounted) setState(() => _smsError = null);
    } catch (_) {
      if (mounted) {
        setState(() {
          _smsError =
              'Collect could not record an account-bound consent. SMS capture remains off.';
        });
      }
    }
    await _refresh();
  }

  Future<void> _disableSms() async {
    try {
      await ref.read(collectRepositoryProvider.notifier).setSmsAccess(false);
      if (mounted) setState(() => _smsError = null);
    } catch (_) {
      if (mounted) {
        setState(() {
          _smsError =
              'Local SMS capture is off, but the server consent audit could not be updated. Try again when online.';
        });
      }
    }
    await _refresh();
  }

  Future<void> _openSmsSettings() async {
    await _smsAccess.openAppSettings();
  }

  Future<void> _openSystemSettings() async {
    await permissions.openAppSettings();
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
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return CollectCard(
      padding: CollectSpacing.cardPaddingComfortable,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CollectToneIcon(icon: icon, tone: tone),
              CollectSpacing.gapW12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    CollectSpacing.gap8,
                    Text(
                      explanation,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.collectColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          CollectSpacing.gap16,
          Wrap(
            spacing: CollectSpacing.x2,
            runSpacing: CollectSpacing.x2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              CollectStatusChip(label: status, tone: tone, icon: icon),
              CollectButton(
                label: actionLabel,
                icon: onAction == null
                    ? CollectIcons.pending
                    : CollectIcons.settings,
                variant: CollectButtonVariant.secondary,
                onPressed: onAction,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
