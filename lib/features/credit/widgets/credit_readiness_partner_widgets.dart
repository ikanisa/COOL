import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_error_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../partners/models/partner.dart';
import '../../partners/widgets/partner_brand_mark.dart';
import '../models/credit_readiness.dart';
import '../models/partner_credit_application.dart';
import '../providers/credit_provider.dart';
import 'credit_readiness_checklist_widgets.dart';

// ── Partner Handoff Section ──────────────────────────────────────────────

/// Shows eligible partner cards.
class PartnerHandoffSection extends StatelessWidget {
  const PartnerHandoffSection({
    required this.partners,
    required this.report,
    super.key,
  });

  final List<Partner> partners;
  final CreditReadinessReport report;

  @override
  Widget build(BuildContext context) {
    if (partners.isEmpty) {
      return const CoolEmptyView(
        message: 'No active finance partners found.',
        compact: true,
        icon: Icons.account_balance_outlined,
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
            onPressed: () => context.push('/partners'),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('View all partners'),
          ),
        ),
      ],
    );
  }
}

/// Shows application pipeline.
class ApplicationPipelineSection extends StatelessWidget {
  const ApplicationPipelineSection({
    required this.applications,
    super.key,
  });

  final List<PartnerCreditApplication> applications;

  @override
  Widget build(BuildContext context) {
    if (applications.isEmpty) {
      return const CoolCard(
        child: CoolEmptyView(
          message: 'No partner applications yet.',
          compact: true,
          icon: Icons.inbox_rounded,
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

/// Loading state for partners.
class PartnersLoadingState extends StatelessWidget {
  const PartnersLoadingState({super.key});

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

/// Simple error card.
class PartnerErrorCard extends StatelessWidget {
  const PartnerErrorCard({required this.error, super.key});

  final String error;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: CoolErrorView(
        message: error,
        compact: true,
      ),
    );
  }
}

// ── Private Widgets ──────────────────────────────────────────────────────

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
              HistoryStatChip(
                label: 'Readiness',
                value: _displayReadinessState(application.readinessState),
              ),
              HistoryStatChip(
                label: 'KYC',
                value: kycStatusLabel(application.kycStatus),
              ),
              HistoryStatChip(
                label: 'Score',
                value: application.creditScore?.toString() ?? 'Pending',
              ),
              if (createdAt != null)
                HistoryStatChip(
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
        return PartnerApplicationComposerSheet(
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

/// Bottom‐sheet for creating partner credit applications.
class PartnerApplicationComposerSheet extends ConsumerStatefulWidget {
  const PartnerApplicationComposerSheet({
    required this.partner,
    required this.report,
    super.key,
  });

  final Partner partner;
  final CreditReadinessReport report;

  @override
  ConsumerState<PartnerApplicationComposerSheet> createState() =>
      _PartnerApplicationComposerSheetState();
}

class _PartnerApplicationComposerSheetState
    extends ConsumerState<PartnerApplicationComposerSheet> {
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
                        if (value == null) return;
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
    if (_isSavingDraft || _isSubmitting) return;
    await _createApplication(submitNow: false);
  }

  Future<void> _submitAndRoute() async {
    if (_isSavingDraft || _isSubmitting) return;
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
      if (!mounted) return;
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

// ── Helpers ──────────────────────────────────────────────────────────────

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
