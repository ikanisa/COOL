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
                body: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    _ScopeCard(
                      title: partner?.name ?? 'Partner workspace',
                      subtitle:
                          'This route is the generic partner-admin foundation for future partner-specific operations.',
                    ),
                    const SizedBox(height: 20),
                    const _SectionCard(
                      title: 'Overview',
                      description:
                          'Partner summary metrics and operational health.',
                    ),
                    const SizedBox(height: 12),
                    const _SectionCard(
                      title: 'Catalog',
                      description:
                          'Partner-owned products, services, or packages.',
                    ),
                    const SizedBox(height: 12),
                    const _SectionCard(
                      title: 'Orders and Payments',
                      description:
                          'Transaction monitoring, finance, and reconciliation queues.',
                    ),
                  ],
                ),
              );
            },
            loading: () => const AdminLoadingScaffold(title: 'Partner Admin'),
            error: (_, _) => const AdminAccessDeniedScaffold(
              title: 'Partner Admin',
              message: 'The partner workspace could not be loaded.',
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
                'Rayon Sports uses its dedicated admin workspace.',
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

class _ScopeCard extends StatelessWidget {
  const _ScopeCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
