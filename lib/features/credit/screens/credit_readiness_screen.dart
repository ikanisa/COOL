import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/cool_layout.dart';
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    final dashboardAsync = ref.watch(creditDashboardProvider);

    return Scaffold(
        backgroundColor: colors.appBackground,
        appBar: AppBar(
          leading: IconButton(
            tooltip: context.l10n.back,
            onPressed: () => context.pop(),
            icon: Icon(Icons.arrow_back_rounded, color: colors.primaryText),
          ),
          title: Text(
            context.l10n.creditReadinessTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              color: colors.primaryText,
            ),
          ),
        ),
        body: CoolScreenBackground(
          primaryColor: colors.info,
          secondaryColor: colors.warning,
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
    final insets = context.coolInsets;

    return SingleChildScrollView(
      padding: insets.fromLTRB(
        CoolSpace.x6,
        CoolSpace.x2,
        CoolSpace.x6,
        CoolLayout.rootBottomClearance,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: CoolSpace.x2),
          ReadinessNextMoveCard(
            report: report,
            dashboard: dashboard,
            user: user,
          ),
          const SizedBox(height: CoolSpace.x4),
          ReadinessChecklistCard(report: report),
          const SizedBox(height: CoolSpace.x5 + 2),
          const SectionTitle(title: 'Recent applications'),
          const SizedBox(height: CoolSpace.x2 + 2),
          applicationsAsync.when(
            data: (applications) =>
                ApplicationPipelineSection(applications: applications),
            loading: () => const PartnersLoadingState(),
            error: (error, _) => PartnerErrorCard(error: error.toString()),
          ),
          const SizedBox(height: CoolSpace.x5 + 2),
          const SectionTitle(title: 'Eligible partners'),
          const SizedBox(height: CoolSpace.x2 + 2),
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
