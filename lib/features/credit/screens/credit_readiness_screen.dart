import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/section_title.dart';
import '../../auth/models/user_profile.dart';
import '../../auth/providers/auth_provider.dart';
import '../../partners/providers/partner_provider.dart';
import '../models/credit_dashboard.dart';
import '../models/credit_readiness.dart';
import '../providers/credit_provider.dart';
import '../widgets/credit_readiness_checklist_widgets.dart';
import '../widgets/credit_readiness_partner_widgets.dart';

class CreditReadinessScreen extends ConsumerWidget {
  const CreditReadinessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final dashboardAsync = ref.watch(creditDashboardProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          'Credit readiness',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
      ),
      body: CoolScreenBackground(
        primaryColor: AppColors.blue,
        secondaryColor: AppColors.yellow,
        child: user == null
            ? const ReadinessEmptyState()
            : dashboardAsync.when(
                data: (dashboard) =>
                    _ReadinessBody(user: user, dashboard: dashboard),
                loading: () => const ReadinessLoadingState(),
                error: (error, _) =>
                    ReadinessErrorState(error: error.toString()),
              ),
      ),
    );
  }
}

class _ReadinessBody extends ConsumerWidget {
  const _ReadinessBody({required this.user, required this.dashboard});

  final UserProfile user;
  final CreditDashboard? dashboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = buildCreditReadinessReport(user: user, dashboard: dashboard);
    final bankPartnersAsync = ref.watch(currentCountryBankPartnersProvider);
    final applicationsAsync = ref.watch(myPartnerApplicationsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          ReadinessNextMoveCard(
            report: report,
            dashboard: dashboard,
            user: user,
          ),
          const SizedBox(height: 16),
          ReadinessChecklistCard(report: report),
          const SizedBox(height: 22),
          const SectionTitle(title: 'Recent applications'),
          const SizedBox(height: 10),
          applicationsAsync.when(
            data: (applications) =>
                ApplicationPipelineSection(applications: applications),
            loading: () => const PartnersLoadingState(),
            error: (error, _) => PartnerErrorCard(error: error.toString()),
          ),
          const SizedBox(height: 22),
          const SectionTitle(title: 'Eligible partners'),
          const SizedBox(height: 10),
          bankPartnersAsync.when(
            loading: () => const PartnersLoadingState(),
            error: (error, _) => PartnerErrorCard(error: error.toString()),
            data: (partners) =>
                PartnerHandoffSection(partners: partners, report: report),
          ),
        ],
      ),
    );
  }
}
