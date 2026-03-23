import 'package:flutter/widgets.dart';

import 'secure_screen_wrapper.dart';

/// Backwards-compatible wrapper for sensitive screens.
///
/// This delegates to [SecureScreenWrapper] so all screenshot protection flows
/// through the shared [ScreenSecurityService] implementation.
@Deprecated('Use SecureScreenWrapper instead.')
class SecureScreen extends StatelessWidget {
  const SecureScreen({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SecureScreenWrapper(child: child);
  }
}
