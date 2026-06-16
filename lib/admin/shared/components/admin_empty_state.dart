import 'package:flutter/material.dart';

import '../../../app/theme/collect_colors.dart';

class AdminEmptyState extends StatelessWidget {
  const AdminEmptyState({required this.title, this.message, super.key});

  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceReadable.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.borderAccent),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.textPrimary,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(
                    Icons.inbox_outlined,
                    color: colors.surfaceReadable,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
