import 'package:flutter/widgets.dart';

import '../../partners/rayon/screens/rayon_home_screen.dart';

/// Backwards-compatible wrapper for callers still importing the legacy home
/// screen path. The primary landing route is now the Rayon-first home surface.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RayonHomeScreen();
  }
}
