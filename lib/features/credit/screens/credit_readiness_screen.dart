import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/section_title.dart';
import '../../auth/models/user_profile.dart';
import '../../auth/providers/auth_provider.dart';
import '../../partners/models/partner.dart';
import '../../partners/providers/partner_provider.dart';
import '../../partners/widgets/partner_brand_mark.dart';
import '../models/credit_dashboard.dart';
import '../models/partner_credit_application.dart';
import '../models/credit_readiness.dart';
import '../providers/credit_provider.dart';

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
            ? const _ReadinessEmptyState()
            : dashboardAsync.when(
                data: (dashboard) =>
                    _ReadinessBody(user: user, dashboard: dashboard),
                loading: () => const _ReadinessLoadingState(),
                error: (error, _) =>
                    _ReadinessErrorState(error: error.toString()),
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
          _NextMoveCard(report: report, dashboard: dashboard, user: user),
          const SizedBox(height: 16),
          _ChecklistCard(report: report),
          const SizedBox(height: 22),
          const SectionTitle(title: 'Recent applications'),
          const SizedBox(height: 10),
          applicationsAsync.when(
            data: (applications) =>
                _ApplicationPipelineSection(applications: applications),
            loading: () => const _PartnersLoadingState(),
            error: (error, _) => _PartnerErrorCard(error: error.toString()),
          ),
          const SizedBox(height: 22),
          const SectionTitle(title: 'Eligible partners'),
          const SizedBox(height: 10),
          bankPartnersAsync.when(
            loading: () => const _PartnersLoadingState(),
            error: (error, _) => _PartnerErrorCard(error: error.toString()),
            data: (partners) =>
                _PartnerHandoffSection(partners: partners, report: report),
          ),
        ],
      ),
    );
  }
}

class _ChecklistCard extends StatelessWidget {
  const _ChecklistCard({required this.report});

  final CreditReadinessReport report;

  @override
  Widget build(BuildContext context) {
    final visibleChecks = report.checks
        .where((check) => !check.isComplete)
        .take(3)
        .toList(growable: false);
    final checksToShow = visibleChecks.isNotEmpty
        ? visibleChecks
        : report.checks.take(2).toList(growable: false);
    final hiddenCount = report.checks.length - checksToShow.length;

    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Readiness checks',
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${report.completedChecks}/${report.totalChecks} checks complete',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.text2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            report.blockingIssues == 0
                ? 'No blocking issues open.'
                : '${report.blockingIssues} blockers need attention.',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          ...checksToShow.map(
            (check) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ChecklistRow(check: check),
            ),
          ),
          if (hiddenCount > 0)
            Text(
              '+$hiddenCount more checks',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.text3,
              ),
            ),
        ],
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.check});

  final CreditReadinessCheck check;

  @override
  Widget build(BuildContext context) {
    final color = check.isComplete
        ? AppColors.accent
        : (check.isBlocking ? AppColors.orange : AppColors.text3);
    final icon = check.isComplete
        ? Icons.check_circle_rounded
        : (check.isBlocking
              ? Icons.error_outline_rounded
              : Icons.radio_button_unchecked_rounded);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: check.isComplete
              ? AppColors.accent.withValues(alpha: 0.18)
              : AppColors.border2,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        check.label,
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    if (check.isBlocking)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Required',
                          style: GoogleFonts.dmSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.orange,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  check.detail,
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text2,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NextMoveCard extends StatelessWidget {
  const _NextMoveCard({
    required this.report,
    required this.dashboard,
    required this.user,
  });

  final CreditReadinessReport report;
  final CreditDashboard? dashboard;
  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    final needsProfileWork =
        report.accountOpening.state == CreditReadinessState.actionNeeded ||
        report.loanApplication.state == CreditReadinessState.actionNeeded;
    final partnerReady =
        report.loanApplication.state == CreditReadinessState.ready ||
        report.loanApplication.state == CreditReadinessState.nearlyReady ||
        report.accountOpening.state == CreditReadinessState.ready ||
        report.accountOpening.state == CreditReadinessState.nearlyReady;

    final headline = needsProfileWork
        ? 'Tighten the profile first'
        : partnerReady
        ? 'The user can move to partners'
        : 'Keep building verified financial history';
    final detail = needsProfileWork
        ? report.accountOpening.nextStep
        : partnerReady
        ? report.loanApplication.nextStep
        : 'Let wallet, savings, and KYC evidence mature first.';

    return CoolCard(
      borderColor: AppColors.purple.withValues(alpha: 0.25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Next step',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.text2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            headline,
            style: GoogleFonts.dmSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HistoryStatChip(
                label: 'KYC',
                value: _kycStatusLabel(user.kycStatus),
              ),
              _HistoryStatChip(
                label: 'Score',
                value: dashboard?.score?.toString() ?? 'Pending',
              ),
              _HistoryStatChip(
                label: 'Checks',
                value: '${report.completedChecks}/${report.totalChecks}',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: CoolButton(
                  label: needsProfileWork ? 'Open profile' : 'Browse partners',
                  icon: needsProfileWork
                      ? Icons.person_outline_rounded
                      : Icons.account_balance_rounded,
                  onTap: () => context.push(
                    needsProfileWork ? AppRoutes.profile : AppRoutes.partners,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ApplicationPipelineSection extends StatelessWidget {
  const _ApplicationPipelineSection({required this.applications});

  final List<PartnerCreditApplication> applications;

  @override
  Widget build(BuildContext context) {
    if (applications.isEmpty) {
      return CoolCard(
        child: Text(
          'No partner applications yet.',
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.text2,
            height: 1.45,
          ),
        ),
      );
    }

    return Column(
      children: applications
          .take(4)
          .map(
            (application) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ApplicationHistoryCard(application: application),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _ApplicationHistoryCard extends StatelessWidget {
  const _ApplicationHistoryCard({required this.application});

  final PartnerCreditApplication application;

  @override
  Widget build(BuildContext context) {
    final statusColor = _applicationStatusColor(application.status);
    final createdAt = application.createdAt?.toLocal();
    final handoffAt = application.lastHandoffAt?.toLocal();
    final dateFormatter = DateFormat('d MMM yyyy');

    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      application.partnerName,
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      application.applicationTypeLabel,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text2,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  application.statusLabel,
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HistoryStatChip(
                label: 'Readiness',
                value: _displayReadinessState(application.readinessState),
              ),
              _HistoryStatChip(
                label: 'KYC',
                value: _kycStatusLabel(application.kycStatus),
              ),
              _HistoryStatChip(
                label: 'Score',
                value: application.creditScore?.toString() ?? 'Pending',
              ),
              if (createdAt != null)
                _HistoryStatChip(
                  label: 'Created',
                  value: dateFormatter.format(createdAt),
                ),
            ],
          ),
          if ((application.requestedProduct?.trim().isNotEmpty ?? false) ||
              (application.applicantNote?.trim().isNotEmpty ?? false) ||
              handoffAt != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (application.requestedProduct?.trim().isNotEmpty ?? false)
                    Text(
                      'Requested: ${application.requestedProduct}',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                  if ((application.requestedProduct?.trim().isNotEmpty ??
                          false) &&
                      application.applicantNote?.trim().isNotEmpty == true)
                    const SizedBox(height: 6),
                  if (application.applicantNote?.trim().isNotEmpty ?? false)
                    Text(
                      application.applicantNote!,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text2,
                        height: 1.45,
                      ),
                    ),
                  if (handoffAt != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Latest handoff: ${dateFormatter.format(handoffAt)} via ${_displayHandoffChannel(application.lastHandoffChannel)}',
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.blue,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryStatChip extends StatelessWidget {
  const _HistoryStatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.text3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _PartnerHandoffSection extends StatelessWidget {
  const _PartnerHandoffSection({required this.partners, required this.report});

  final List<Partner> partners;
  final CreditReadinessReport report;

  @override
  Widget build(BuildContext context) {
    if (partners.isEmpty) {
      return const _PartnerErrorCard(
        error: 'No active finance partners found.',
      );
    }

    final visiblePartners = partners.take(3).toList(growable: false);

    return Column(
      children: [
        ...visiblePartners.map(
          (partner) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _PartnerReadinessCard(partner: partner, report: report),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.push(AppRoutes.partners),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('View all partners'),
          ),
        ),
      ],
    );
  }
}

class _PartnerReadinessCard extends StatelessWidget {
  const _PartnerReadinessCard({required this.partner, required this.report});

  final Partner partner;
  final CreditReadinessReport report;

  Future<void> _startApplication(BuildContext context) async {
    final shouldOpenPartner = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _PartnerApplicationComposerSheet(
          partner: partner,
          report: report,
        );
      },
    );

    if (shouldOpenPartner == true && context.mounted) {
      context.push('/partners/${partner.slug}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final loanState = report.loanApplication.state;
    final accountState = report.accountOpening.state;
    final canDiscussLoans =
        loanState == CreditReadinessState.ready ||
        loanState == CreditReadinessState.nearlyReady;
    final canStartAccount =
        accountState == CreditReadinessState.ready ||
        accountState == CreditReadinessState.nearlyReady;

    final recommendation = canDiscussLoans
        ? 'Best fit: review lending products.'
        : canStartAccount
        ? 'Best fit: start with account or savings onboarding.'
        : 'Best fit: resolve profile and KYC blockers first.';
    final buttonLabel = canDiscussLoans
        ? 'Open lending'
        : canStartAccount
        ? 'Open account'
        : 'View partner';

    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      partner.name,
                      style: GoogleFonts.dmSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      partner.subtitle ??
                          partner.description ??
                          'Finance partner',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text2,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              PartnerBrandMark(
                partner: partner,
                width: 104,
                height: 52,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border2),
            ),
            child: Text(
              recommendation,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 12),
          CoolButton(
            label: buttonLabel,
            variant: canDiscussLoans || canStartAccount
                ? CoolButtonVariant.primary
                : CoolButtonVariant.secondary,
            onTap: () => _startApplication(context),
          ),
        ],
      ),
    );
  }
}

class _PartnerApplicationComposerSheet extends ConsumerStatefulWidget {
  const _PartnerApplicationComposerSheet({
    required this.partner,
    required this.report,
  });

  final Partner partner;
  final CreditReadinessReport report;

  @override
  ConsumerState<_PartnerApplicationComposerSheet> createState() =>
      _PartnerApplicationComposerSheetState();
}

class _PartnerApplicationComposerSheetState
    extends ConsumerState<_PartnerApplicationComposerSheet> {
  late final TextEditingController _productController;
  late final TextEditingController _noteController;
  late String _applicationType;
  bool _isSavingDraft = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _applicationType = _recommendedApplicationType(widget.report);
    _productController = TextEditingController(
      text: _applicationType == 'loan' ? 'Loan discussion' : 'Account opening',
    );
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _productController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  CreditReadinessJourney get _selectedJourney => _applicationType == 'loan'
      ? widget.report.loanApplication
      : widget.report.accountOpening;

  bool get _canRouteNow =>
      _selectedJourney.state == CreditReadinessState.ready ||
      _selectedJourney.state == CreditReadinessState.nearlyReady;

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, viewInsets + 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border2),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.border2,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Text(
                'Create partner application',
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.partner.name,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.blue,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _stateColor(
                    _selectedJourney.state,
                  ).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _stateColor(
                      _selectedJourney.state,
                    ).withValues(alpha: 0.22),
                  ),
                ),
                child: Text(
                  '${_selectedJourney.title}: ${_selectedJourney.summary}',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _applicationType,
                decoration: _sheetInputDecoration(label: 'Application path'),
                items: const [
                  DropdownMenuItem(
                    value: 'loan',
                    child: Text('Loan application'),
                  ),
                  DropdownMenuItem(
                    value: 'account_opening',
                    child: Text('Account opening'),
                  ),
                ],
                onChanged: (_isSavingDraft || _isSubmitting)
                    ? null
                    : (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _applicationType = value;
                          if (_productController.text.trim().isEmpty ||
                              _productController.text == 'Loan discussion' ||
                              _productController.text == 'Account opening') {
                            _productController.text = value == 'loan'
                                ? 'Loan discussion'
                                : 'Account opening';
                          }
                        });
                      },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _productController,
                enabled: !_isSavingDraft && !_isSubmitting,
                decoration: _sheetInputDecoration(
                  label: 'Requested product',
                  hint: 'Example: group loan, savings account',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                enabled: !_isSavingDraft && !_isSubmitting,
                maxLines: 3,
                decoration: _sheetInputDecoration(
                  label: 'Internal note',
                  hint: 'Anything the partner handoff should remember',
                ),
              ),
              if (!_canRouteNow) ...[
                const SizedBox(height: 12),
                Text(
                  'Not ready for partner routing. Save as draft and continue.',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.orange,
                    height: 1.45,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: CoolButton(
                      label: 'Save Draft',
                      variant: CoolButtonVariant.secondary,
                      isLoading: _isSavingDraft,
                      onTap: _isSubmitting ? () {} : _saveDraft,
                    ),
                  ),
                  if (_canRouteNow) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: CoolButton(
                        label: 'Save & Open Partner',
                        isLoading: _isSubmitting,
                        onTap: _isSavingDraft ? () {} : _submitAndRoute,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveDraft() async {
    if (_isSavingDraft || _isSubmitting) {
      return;
    }
    await _createApplication(submitNow: false);
  }

  Future<void> _submitAndRoute() async {
    if (_isSavingDraft || _isSubmitting) {
      return;
    }
    await _createApplication(submitNow: true);
  }

  Future<void> _createApplication({required bool submitNow}) async {
    setState(() {
      if (submitNow) {
        _isSubmitting = true;
      } else {
        _isSavingDraft = true;
      }
    });

    try {
      await ref
          .read(creditApplicationRepositoryProvider)
          .createApplication(
            partner: widget.partner,
            applicationType: _applicationType,
            readinessState: _serializeReadinessState(_selectedJourney.state),
            requestedProduct: _productController.text.trim(),
            applicantNote: _noteController.text.trim(),
            submitNow: submitNow,
            destinationPath: '/partners/${widget.partner.slug}',
          );
      ref.invalidate(myPartnerApplicationsProvider);
      if (!mounted) {
        return;
      }
      if (mounted) {
        final msg = submitNow
            ? 'Application saved and partner handoff recorded.'
            : 'Application draft saved.';
        CoolToast.success(context, msg);
      }
      Navigator.of(context).pop(submitNow);
    } catch (error) {
      if (mounted) {
        CoolToast.error(context, 'Could not save application: $error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingDraft = false;
          _isSubmitting = false;
        });
      }
    }
  }
}

class _PartnersLoadingState extends StatelessWidget {
  const _PartnersLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        CoolSkeleton.card(),
        SizedBox(height: 12),
        CoolSkeleton.card(),
      ],
    );
  }
}

class _PartnerErrorCard extends StatelessWidget {
  const _PartnerErrorCard({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Text(
        error,
        style: GoogleFonts.dmSans(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.text2,
        ),
      ),
    );
  }
}

class _ReadinessLoadingState extends StatelessWidget {
  const _ReadinessLoadingState();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(18, 8, 18, 96),
      child: Column(
        children: [
          CoolSkeleton.card(),
          SizedBox(height: 18),
          CoolSkeleton.card(),
          SizedBox(height: 18),
          CoolSkeleton.card(),
        ],
      ),
    );
  }
}

class _ReadinessErrorState extends StatelessWidget {
  const _ReadinessErrorState({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: CoolCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 34,
                color: AppColors.orange,
              ),
              const SizedBox(height: 12),
              Text(
                'Could not load readiness data.',
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error,
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text2,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadinessEmptyState extends StatelessWidget {
  const _ReadinessEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: CoolCard(
          child: Text(
            'Sign in to review formal profile, credit, and bank-onboarding readiness.',
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.45,
            ),
          ),
        ),
      ),
    );
  }
}

InputDecoration _sheetInputDecoration({required String label, String? hint}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    filled: true,
    fillColor: AppColors.surface2,
    labelStyle: GoogleFonts.dmSans(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.text2,
    ),
    hintStyle: GoogleFonts.dmSans(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: AppColors.text3,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.border2),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.blue),
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.border2),
    ),
  );
}

String _kycStatusLabel(String status) {
  return switch (status) {
    'verified' => 'Verified',
    'pending_review' => 'Pending review',
    'rejected' => 'Rejected',
    _ => 'Unverified',
  };
}

String _serializeReadinessState(CreditReadinessState state) {
  return switch (state) {
    CreditReadinessState.ready => 'ready',
    CreditReadinessState.nearlyReady => 'nearly_ready',
    CreditReadinessState.building => 'building',
    CreditReadinessState.actionNeeded => 'action_needed',
  };
}

String _displayReadinessState(String state) {
  return switch (state) {
    'ready' => 'Ready',
    'nearly_ready' => 'Nearly ready',
    'action_needed' => 'Action needed',
    _ => 'Building',
  };
}

String _displayHandoffChannel(String? channel) {
  return switch (channel) {
    'in_app_redirect' => 'in-app redirect',
    'phone' => 'phone',
    'email' => 'email',
    'whatsapp' => 'WhatsApp',
    'branch' => 'branch',
    'manual' => 'manual',
    _ => 'handoff',
  };
}

String _recommendedApplicationType(CreditReadinessReport report) {
  if (report.loanApplication.state == CreditReadinessState.ready ||
      report.loanApplication.state == CreditReadinessState.nearlyReady) {
    return 'loan';
  }
  return 'account_opening';
}

Color _applicationStatusColor(String status) {
  return switch (status) {
    'draft' => AppColors.text3,
    'partner_routed' => AppColors.blue,
    'in_review' => AppColors.yellow,
    'partner_contacted' => AppColors.accent,
    'closed' => AppColors.text2,
    'cancelled' => AppColors.orange,
    _ => AppColors.text3,
  };
}

Color _stateColor(CreditReadinessState state) {
  return switch (state) {
    CreditReadinessState.ready => AppColors.accent,
    CreditReadinessState.nearlyReady => AppColors.blue,
    CreditReadinessState.building => AppColors.yellow,
    CreditReadinessState.actionNeeded => AppColors.orange,
  };
}
