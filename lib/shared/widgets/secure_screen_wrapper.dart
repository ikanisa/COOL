import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/engagement_providers.dart';
import '../../core/services/screen_security_service.dart';

/// A wrapper that enables FLAG_SECURE (screenshot protection)
/// for the duration that its child is visible.
///
/// Usage: wrap sensitive screen routes in the router:
/// ```dart
/// SecureScreenWrapper(child: MomoScreen())
/// ```
class SecureScreenWrapper extends ConsumerStatefulWidget {
  const SecureScreenWrapper({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<SecureScreenWrapper> createState() =>
      _SecureScreenWrapperState();
}

class _SecureScreenWrapperState extends ConsumerState<SecureScreenWrapper> {
  late final ScreenSecurityService _screenSecurityService;

  @override
  void initState() {
    super.initState();
    _screenSecurityService = ref.read(screenSecurityServiceProvider);
    // Enable screenshot protection when this screen is shown.
    _screenSecurityService.enableSecureMode();
  }

  @override
  void dispose() {
    // Disable screenshot protection when navigating away.
    _screenSecurityService.disableSecureMode();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
