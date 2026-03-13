import 'package:flutter/material.dart';

import '../../../shared/widgets/cool_error_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';

class RayonLoadingView extends StatelessWidget {
  const RayonLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      physics: AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: CoolSkeletonList(itemCount: 4),
      ),
    );
  }
}

class RayonInlineLoadingView extends StatelessWidget {
  const RayonInlineLoadingView({this.compact = false, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 16 : 24),
      child: CoolSkeletonList(itemCount: compact ? 2 : 3),
    );
  }
}

class RayonInlineBusyIndicator extends StatelessWidget {
  const RayonInlineBusyIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const CoolSkeleton(width: 20, height: 20, borderRadius: 10);
  }
}

class RayonInlineEmptyView extends StatelessWidget {
  const RayonInlineEmptyView({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: CoolErrorView(
        message: message,
        compact: true,
        icon: Icons.inbox_rounded,
      ),
    );
  }
}

class RayonErrorView extends StatelessWidget {
  const RayonErrorView({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 8),
      child: CoolErrorView(
        message: message,
        onRetry: onRetry,
        icon: Icons.sports_soccer_rounded,
      ),
    );
  }
}
