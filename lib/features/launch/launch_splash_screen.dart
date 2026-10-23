import 'package:flutter/material.dart';

import '../../shared/widgets/collect_components.dart';

/// A non-branded routing surface used only while persisted session state loads.
///
/// Android owns the single visible Collect launch screen. Keeping this surface
/// the same colour prevents a second Flutter splash from appearing between the
/// Android starting window and the first real application route.
class LaunchSplashScreen extends StatelessWidget {
  const LaunchSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: CollectColors.referenceChromeBlack,
      child: SizedBox.expand(),
    );
  }
}
