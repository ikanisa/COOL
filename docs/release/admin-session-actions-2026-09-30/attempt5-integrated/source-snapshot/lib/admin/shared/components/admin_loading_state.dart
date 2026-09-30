import 'package:flutter/material.dart';

import '../../../shared/widgets/collect_components.dart';

class AdminLoadingState extends StatelessWidget {
  const AdminLoadingState({
    this.title = 'Loading admin data',
    this.message = 'Refreshing the live operations view.',
    super.key,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: LoadingStatePanel(title: title, message: message, lines: 4),
      ),
    );
  }
}
