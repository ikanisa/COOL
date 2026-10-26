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
  bool _requestingSms = false;
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
    final captureAvailable = ref.watch(momoReceiptCaptureAvailableProvider);
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
              if (captureAvailable)
                _PermissionCard(
                  icon: CollectIcons.shield,
                  title: 'M-Money SMS',
                  status: _loading
                      ? 'Checking'
                      : _momoSmsStatus.enabled
                      ? 'Allowed'
                      : 'Not allowed',
                  actionLabel: _momoSmsStatus.enabled
                      ? 'Turn off'
                      : _momoSmsStatus.permanentlyDenied
                      ? 'Phone settings'
                      : 'Allow',
                  onAction: _loading || _requestingSms
                      ? null
                      : _momoSmsStatus.enabled
                      ? _disableMomoSms
                      : _momoSmsStatus.permanentlyDenied
                      ? const SmsAccessChannel().openAppSettings
                      : _requestMomoSms,
                ),
              if (captureAvailable && _momoSmsStatus.queueNeedsReview)
                Padding(
                  padding: const EdgeInsets.only(bottom: CollectSpacing.x2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _momoSmsStatus.enabled
                            ? 'Some SMS uploads need review. Originals stay on this phone.'
                            : 'Some SMS uploads need review. Allow SMS access to retry; originals stay on this phone.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.collectColors.textSecondary,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed:
                              _loading ||
                                  _requestingSms ||
                                  !_momoSmsStatus.enabled
                              ? null
                              : _retryMomoSms,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            foregroundColor: context.collectColors.textPrimary,
                          ),
                          child: const Text('Retry uploads'),
                        ),
                      ),
                    ],
                  ),
                ),
              ValueListenableBuilder<CollectNotificationStatus>(
                valueListenable: ref
                    .watch(collectNotificationServiceProvider)
                    .registrationStatus,
                builder: (context, status, _) => _PermissionCard(
                  icon: CollectIcons.pending,
                  title: 'Notifications',
                  status: status.message,
                  actionLabel: switch (status) {
                    CollectNotificationStatus.checking => 'Connecting',
                    CollectNotificationStatus.signInRequired => 'Sign in again',
                    CollectNotificationStatus.ready ||
                    CollectNotificationStatus.permissionDenied =>
                      'Phone settings',
                    CollectNotificationStatus.notRequested => 'Allow',
                    _ => 'Retry',
                  },
                  onAction:
                      _loading || status == CollectNotificationStatus.checking
                      ? null
                      : switch (status) {
                          CollectNotificationStatus.signInRequired =>
                            () => signInForNotifications(context, ref),
                          CollectNotificationStatus.ready ||
                          CollectNotificationStatus.permissionDenied =>
                            permissions.openAppSettings,
                          _ => _requestNotifications,
                        },
                ),
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
    final captureAvailable = ref.read(momoReceiptCaptureAvailableProvider);
    final results = await Future.wait<Object>([
      permissions.Permission.camera.status,
      if (captureAvailable)
        ref.read(collectRepositoryProvider.notifier).refreshSmsAccessStatus(),
    ]);
    if (!mounted) return;
    setState(() {
      _cameraStatus = results[0] as permissions.PermissionStatus;
      _momoSmsStatus = captureAvailable
          ? results[1] as SmsAccessStatus
          : const SmsAccessStatus.unavailable();
      _loading = false;
    });
    if (service.registrationStatus.value !=
        CollectNotificationStatus.signInRequired) {
      unawaited(
        service.registerDevice(ref.read(collectRepositoryProvider.notifier)),
      );
    }
  }

  Future<void> _requestNotifications() async {
    final service = ref.read(collectNotificationServiceProvider);
    await service.enableDevice(ref.read(collectRepositoryProvider.notifier));
  }

  Future<void> _requestCamera() async {
    await permissions.Permission.camera.request();
    await _refresh();
  }

  Future<void> _requestMomoSms() async {
    if (_requestingSms || !ref.read(momoReceiptCaptureAvailableProvider)) {
      return;
    }
    final expectedOwner = ref
        .read(collectRepositoryProvider)
        .currentProfile
        ?.id;
    if (expectedOwner == null) return;
    setState(() => _requestingSms = true);
    try {
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
                    title: 'Allow M-Money SMS uploads?',
                    message: 'Share incoming M-Money messages with Collect.',
                    education:
                        'New M-Money SMS received after you allow access are '
                        'linked to your signed-in account and uploaded for '
                        'Admin review. Original messages are protected and '
                        'wait on this device while offline. Uploading a message '
                        'never credits a payment automatically. You can turn '
                        'access off here at any time.',
                    tone: CollectStatusTone.warning,
                  ),
                  CollectSpacing.gap16,
                  CollectButton(
                    label: 'Allow SMS access',
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
          ref.read(collectRepositoryProvider).currentProfile?.id !=
              expectedOwner ||
          !ref.read(momoReceiptCaptureAvailableProvider)) {
        return;
      }
      try {
        final enabled = await ref
            .read(collectRepositoryProvider.notifier)
            .setSmsAccess(true, expectedOwnerUserId: expectedOwner);
        if (!enabled &&
            mounted &&
            ref.read(collectRepositoryProvider).currentProfile?.id ==
                expectedOwner) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('M-Money SMS access was not enabled.'),
            ),
          );
        }
      } catch (_) {
        if (mounted &&
            ref.read(collectRepositoryProvider).currentProfile?.id ==
                expectedOwner) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('M-Money SMS access was not enabled.'),
            ),
          );
        }
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => _requestingSms = false);
    }
  }

  Future<void> _disableMomoSms() async {
    await ref.read(collectRepositoryProvider.notifier).setSmsAccess(false);
    await _refresh();
  }

  Future<void> _retryMomoSms() async {
    if (_requestingSms || !ref.read(momoReceiptCaptureAvailableProvider)) {
      return;
    }
    final owner = ref.read(collectRepositoryProvider).currentProfile?.id;
    if (owner == null) return;
    setState(() => _requestingSms = true);
    try {
      await ref
          .read(collectRepositoryProvider.notifier)
          .retryRejectedSmsAccess(expectedOwnerUserId: owner);
    } catch (_) {
      if (mounted &&
          ref.read(collectRepositoryProvider).currentProfile?.id == owner) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'SMS uploads remain queued. Try again when connected.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        await _refresh();
        if (mounted) setState(() => _requestingSms = false);
      }
    }
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
              Semantics(
                liveRegion: true,
                child: Text(
                  status,
                  key: ValueKey('permission_status_$title'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.collectColors.textSecondary,
                  ),
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
