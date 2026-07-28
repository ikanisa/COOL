import 'package:flutter/material.dart';

import '../../app/theme/collect_typography.dart';

class AdminErrorBoundary extends StatelessWidget {
  const AdminErrorBoundary({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class AdminSafeErrorPanel extends StatelessWidget {
  const AdminSafeErrorPanel({required this.error, this.onRetry, super.key});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      label: 'Admin request failed',
      child: Card(
        color: colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      adminSafeErrorMessage(error),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onErrorContainer,
                        fontWeight: CollectTypography.weightBold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Retry the request. If it continues, escalate with the current route and timestamp.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                    if (onRetry != null) ...[
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String adminSafeErrorMessage(Object error) {
  final message = error.toString().toLowerCase();
  if (message.contains('authentication required') ||
      message.contains('jwt') ||
      message.contains('session')) {
    return 'Your admin session needs to be refreshed.';
  }
  if (message.contains('permission') ||
      message.contains('not authorized') ||
      message.contains('denied')) {
    return 'This admin profile is not allowed to perform that action.';
  }
  if (message.contains('network') ||
      message.contains('socket') ||
      message.contains('timeout') ||
      message.contains('failed host lookup')) {
    return 'The admin service could not be reached.';
  }
  return 'The admin request could not be completed.';
}
