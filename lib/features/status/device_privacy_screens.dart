import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;

import '../../core/notifications/collect_notification_service.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/money_format.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/providers/collect_app_state.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/utils/support_contact.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

part 'device_notification_center.dart';
part 'device_permission_screens.dart';
part 'device_privacy_data_screen.dart';
part 'device_support_screen.dart';

Future<bool> _enableNativeNotifications(WidgetRef ref) async {
  final service = ref.read(collectNotificationServiceProvider);
  final granted = await service.requestPermission();
  if (!granted) return false;
  final repository = ref.read(collectRepositoryProvider.notifier);
  await service.registerDevice(repository);
  await service.showNotification(
    title: 'Collect notifications enabled',
    body:
        'Payment reminders, group updates, and security notices can now appear on this device.',
    payload: '/notifications',
  );
  return true;
}
