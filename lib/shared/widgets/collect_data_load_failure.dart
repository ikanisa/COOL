import 'package:flutter/material.dart';

import 'collect_components.dart';

/// A failed initial read is not a zero balance or an empty account.
/// Keep recovery local to the affected content and never expose raw API errors.
class CollectDataLoadFailure extends StatelessWidget {
  const CollectDataLoadFailure({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: MinimalStatePanel(
        icon: CollectIcons.sync,
        title: 'Could not load data',
        message: '',
        tone: CollectStatusTone.warning,
        primaryAction: CollectButton(
          label: 'Retry',
          icon: CollectIcons.sync,
          onPressed: onRetry,
          expand: true,
        ),
      ),
    );
  }
}
