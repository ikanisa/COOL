import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/engagement_providers.dart';

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
  @override
  void initState() {
    super.initState();
    // Enable screenshot protection when this screen is shown.
    ref.read(screenSecurityServiceProvider).enableSecureMode();
  }

  @override
  void dispose() {
    // Disable screenshot protection when navigating away.
    ref.read(screenSecurityServiceProvider).disableSecureMode();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
