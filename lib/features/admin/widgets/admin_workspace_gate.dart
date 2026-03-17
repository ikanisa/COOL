import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/admin_workspace_access_provider.dart';
import '../../../core/l10n/l10n.dart';

class AdminLoadingScaffold extends StatelessWidget {
  const AdminLoadingScaffold({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.text),
        title: Text(
          title,
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
      ),
      body: const Center(child: CircularProgressIndicator()),
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
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.text),
        title: Text(
          title,
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 42,
                color: AppColors.text3,
              ),
              const SizedBox(height: 12),
              Text(
                'Access denied',
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text2,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () => context.go(fallbackLocation),
                child: Text(context.l10n.backToAdmin),
              ),
            ],
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
      message: 'This workspace is reserved',
    );
  }
}

class PartnerAdminGate extends ConsumerWidget {
  const PartnerAdminGate({
    required this.partnerId,
    required this.child,
    super.key,
  });

  final String partnerId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(adminWorkspaceAccessProvider);
    if (access.canAccessPartnerId(partnerId)) {
      return child;
    }
    return AdminAccessDeniedScaffold(
      title: context.l10n.partnerAdmin,
      message:
          'You do not have',
    );
  }
}

class BankAdminGate extends ConsumerWidget {
  const BankAdminGate({required this.partnerId, required this.child, super.key});

  final String partnerId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(adminWorkspaceAccessProvider);
    if (access.canAccessBankId(partnerId)) {
      return child;
    }
    return const AdminAccessDeniedScaffold(
      title: 'Bank Admin',
      message:
          'You do not have',
    );
  }
}

class RayonAdminGate extends ConsumerWidget {
  const RayonAdminGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accessAsync = ref.watch(rayonAdminAccessProvider);
    return accessAsync.when(
      data: (hasAccess) {
        if (hasAccess) {
          return child;
        }
        return const AdminAccessDeniedScaffold(
          title: 'Rayon Sports Admin',
          message:
              'You do not have',
        );
      },
      loading: () => const AdminLoadingScaffold(title: 'Rayon Sports Admin'),
      error: (_, _) => const AdminAccessDeniedScaffold(
        title: 'Rayon Sports Admin',
        message: 'The Rayon Sports admin',
      ),
    );
  }
}