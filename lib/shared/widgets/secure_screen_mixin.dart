import 'package:flutter/widgets.dart';
import 'package:no_screenshot/no_screenshot.dart';

/// Mixin for [State] that prevents screenshots & screen recording
/// while the screen is active (Android: FLAG_SECURE, iOS: overlay).
///
/// Usage:
/// ```dart
/// class _MyScreenState extends State<MyScreen> with SecureScreenMixin {
///   // …
/// }
/// ```
///
/// The mixin calls [NoScreenshot.screenshotOff] in [initState] and
/// [NoScreenshot.screenshotOn] in [dispose], so the protection is
/// scoped to this screen's lifecycle.
mixin SecureScreenMixin<T extends StatefulWidget> on State<T> {
  final _noScreenshot = NoScreenshot.instance;

  @override
  void initState() {
    super.initState();
    _setSecure();
  }

  @override
  void dispose() {
    _clearSecure();
    super.dispose();
  }

  Future<void> _setSecure() async {
    try {
      await _noScreenshot.screenshotOff();
    } catch (e) {
      debugPrint('[SecureScreen] Failed to enable FLAG_SECURE: $e');
    }
  }

  Future<void> _clearSecure() async {
    try {
      await _noScreenshot.screenshotOn();
    } catch (e) {
      debugPrint('[SecureScreen] Failed to clear FLAG_SECURE: $e');
    }
  }
}

/// Wrapper widget that prevents screenshots while its child is mounted.
///
/// Use for screens that extend [ConsumerWidget] / [StatelessWidget]
/// and can't use the [SecureScreenMixin]:
/// ```dart
/// @override
/// Widget build(BuildContext context, WidgetRef ref) {
///   return SecureScreen(child: Scaffold(…));
/// }
/// ```
class SecureScreen extends StatefulWidget {
  const SecureScreen({required this.child, super.key});
  final Widget child;

  @override
  State<SecureScreen> createState() => _SecureScreenState();
}

class _SecureScreenState extends State<SecureScreen>
    with SecureScreenMixin<SecureScreen> {
  @override
  Widget build(BuildContext context) => widget.child;
}
