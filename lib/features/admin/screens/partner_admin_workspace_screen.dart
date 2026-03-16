import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../partners/providers/partner_provider.dart';
import '../widgets/admin_workspace_gate.dart';

class PartnerAdminWorkspaceScreen extends ConsumerWidget {
  const PartnerAdminWorkspaceScreen({required this.partnerId, super.key});

  final String partnerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PartnerAdminGate(
      partnerId: partnerId,
      child: ref
          .watch(partnerByIdProvider(partnerId))
          .when(
            data: (partner) {
              if (partner?.slug == 'rayon-sports') {
                return const RayonAdminGate(child: _RayonForwardingView());
              }

              return Scaffold(
                backgroundColor: AppColors.bg,
                appBar: AppBar(
                  backgroundColor: AppColors.surface,
                  elevation: 0,
                  iconTheme: IconThemeData(color: AppColors.text),
                  title: Text(
                    '${partner?.name ?? 'Partner'} Admin',
                    style: GoogleFonts.dmSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppColors.blue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            Icons.construction_rounded,
                            size: 32,
                            color: AppColors.blue,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Coming Soon',
                          style: GoogleFonts.dmSans(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${partner?.name ?? 'Partner'} workspace is under development. '
                          'Partner-specific admin tools will be available here once ready.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.text2,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                        OutlinedButton.icon(
                          onPressed: () => context.go(AppRoutes.admin),
                          icon: const Icon(Icons.arrow_back_rounded, size: 16),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.text2,
                            side: BorderSide(color: AppColors.border),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          label: Text(
                            'Back to workspaces',
                            style: GoogleFonts.dmSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
            loading: () => const AdminLoadingScaffold(title: 'Partner Admin'),
            error: (_, _) => const AdminAccessDeniedScaffold(
              title: 'Partner Admin',
              message: 'The partner workspace could not be loaded. Please try again.',
            ),
          ),
    );
  }
}

class _RayonForwardingView extends StatelessWidget {
  const _RayonForwardingView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.text),
        title: Text(
          'Partner Admin',
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
              Text(
                'Rayon Sports uses its',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => context.go(AppRoutes.adminRayon),
                child: const Text('Open Rayon Sports Admin'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



