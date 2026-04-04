import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../providers/admin_workspace_access_provider.dart';

const BorderRadius _adminWorkspaceGateHeroRadius = BorderRadius.all(
  Radius.circular(CoolRadii.lg),
);

class AdminLoadingScaffold extends StatelessWidget {
  const AdminLoadingScaffold({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return _AdminStateScaffold(
      title: title,
      child: CoolCard(
        backgroundColor: colors.cardSurfaceStrong,
        borderColor: colors.borderStrong,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colors.analyticsSurface,
                borderRadius: _adminWorkspaceGateHeroRadius,
                border: Border.all(color: colors.borderStrong),
              ),
              alignment: Alignment.center,
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.8,
                  color: colors.accent,
                ),
              ),
            ),
            const SizedBox(height: CoolSpace.x6),
            Text(
              'Loading workspace',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: colors.primaryText,
              ),
            ),
            const SizedBox(height: CoolSpace.x3),
            Text(
              'Access checks, role policy, and workspace data are being prepared.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminAccessDeniedScaffold extends StatelessWidget {
  const AdminAccessDeniedScaffold({
    required this.title,
    required this.message,
    this.fallbackLocation = AppRoutes.admin,
    super.key,
  });

  final String title;
  final String message;
  final String fallbackLocation;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return _AdminStateScaffold(
      title: title,
      child: CoolCard(
        backgroundColor: colors.cardSurfaceStrong,
        borderColor: colors.borderStrong,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colors.danger.withValues(alpha: 0.12),
                borderRadius: _adminWorkspaceGateHeroRadius,
                border: Border.all(
                  color: colors.danger.withValues(alpha: 0.24),
                ),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.lock_outline_rounded,
                size: 34,
                color: colors.danger,
              ),
            ),
            const SizedBox(height: CoolSpace.x6),
            Text(
              'Access denied',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: colors.primaryText,
              ),
            ),
            const SizedBox(height: CoolSpace.x3),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: CoolSpace.x6),
            CoolButton(
              label: context.l10n.backToAdmin,
              variant: CoolButtonVariant.secondary,
              onTap: () => context.go(fallbackLocation),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminStateScaffold extends StatelessWidget {
  const _AdminStateScaffold({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return CoolScreenBackground(
      showGlow: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: colors.primaryText),
          title: Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SingleChildScrollView(
                padding: CoolSpace.pagePadding,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PlatformAdminGate extends ConsumerWidget {
  const PlatformAdminGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(adminWorkspaceAccessProvider);
    if (access.hasPlatformAccess) {
      return child;
    }
    return AdminAccessDeniedScaffold(
      title: context.l10n.platformAdmin,
      message: 'This workspace is reserved for platform administrators.',
    );
  }
}

class BankAdminWorkspaceGate extends ConsumerWidget {
  const BankAdminWorkspaceGate({
    required this.bankId,
    required this.child,
    super.key,
  });

  final String bankId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(adminWorkspaceAccessProvider);
    if (access.canAccessBankId(bankId)) {
      return child;
    }
    return const AdminAccessDeniedScaffold(
      title: 'Bank Workspace',
      message: 'This bank workspace is outside your assigned scope.',
    );
  }
}
