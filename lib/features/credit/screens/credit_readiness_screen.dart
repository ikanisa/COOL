import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/l10n/l10n.dart';

import '../../../core/theme/cool_palette.dart';
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
import '../../../shared/widgets/secure_screen_mixin.dart';

class CreditReadinessScreen extends ConsumerWidget {
  const CreditReadinessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.coolPalette;
    final user = ref.watch(currentUserProvider);
    final dashboardAsync = ref.watch(creditDashboardProvider);

    return SecureScreen(child: Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.l10n.back,
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          context.l10n.creditReadinessTitle,
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: palette.text,
          ),
        ),
      ),
      body: CoolScreenBackground(
        primaryColor: palette.blue,
        secondaryColor: palette.yellow,
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
    ));
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
