import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';
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
    final insets = context.coolInsets;
    if (partners.isEmpty) {
      return const CoolEmptyView(
        message: 'No active finance found',
        compact: true,
        icon: Icons.account_balance_outlined,
      );
    }

    final visiblePartners = partners.take(3).toList(growable: false);

    return Column(
      children: [
        ...visiblePartners.map(
          (partner) => Padding(
            padding: insets.only(bottom: CoolSpace.x3),
            child: _PartnerReadinessCard(partner: partner, report: report),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.push('/partners'),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(context.l10n.viewAllPartners),
          ),
        ),
      ],
    );
  }
}

/// Shows application pipeline.
class ApplicationPipelineSection extends StatelessWidget {
  const ApplicationPipelineSection({required this.applications, super.key});

  final List<PartnerCreditApplication> applications;

  @override
  Widget build(BuildContext context) {
    final insets = context.coolInsets;
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
              padding: insets.only(bottom: CoolSpace.x3),
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
        SizedBox(height: CoolSpace.x3),
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
    return CoolCard(child: CoolErrorView(message: error, compact: true));
  }
}

class _ApplicationHistoryCard extends StatelessWidget {
  const _ApplicationHistoryCard({required this.application});

  final PartnerCreditApplication application;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final insets = context.coolInsets;
    final statusColor = _applicationStatusColor(application.status, colors);
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
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.primaryText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x1),
                    Text(
                      application.applicationTypeLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: insets.symmetric(
                  horizontal: CoolSpace.x2 + 2,
                  vertical: CoolSpace.x1 + 1,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: const BorderRadius.all(
                    Radius.circular(CoolRadii.pill),
                  ),
                ),
                child: Text(
                  application.statusLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x3),
          Wrap(
            spacing: CoolSpace.x2 + 2,
            runSpacing: CoolSpace.x2 + 2,
            children: [
              HistoryStatChip(
                label: context.l10n.readiness,
                value: _displayReadinessState(application.readinessState),
              ),
              HistoryStatChip(
                label: context.l10n.kyc,
                value: kycStatusLabel(application.kycStatus),
              ),
              HistoryStatChip(
                label: context.l10n.score,
                value: application.creditScore?.toString() ?? 'Pending',
              ),
              if (createdAt != null)
                HistoryStatChip(
                  label: context.l10n.created,
                  value: dateFormatter.format(createdAt),
                ),
            ],
          ),
          if ((application.requestedProduct?.trim().isNotEmpty ?? false) ||
              (application.applicantNote?.trim().isNotEmpty ?? false) ||
              handoffAt != null) ...[
            const SizedBox(height: CoolSpace.x3),
            Container(
              width: double.infinity,
              padding: insets.all(CoolSpace.x3),
              decoration: BoxDecoration(
                color: colors.cardSurface,
                borderRadius: const BorderRadius.all(
                  Radius.circular(CoolRadii.xs),
                ),
                border: Border.all(color: colors.borderStrong),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (application.requestedProduct?.trim().isNotEmpty ?? false)
                    Text(
                      'Requested: ${application.requestedProduct}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.primaryText,
                      ),
                    ),
                  if ((application.requestedProduct?.trim().isNotEmpty ??
                          false) &&
                      application.applicantNote?.trim().isNotEmpty == true)
                    const SizedBox(height: CoolSpace.x1 + 2),
                  if (application.applicantNote?.trim().isNotEmpty ?? false)
                    Text(
                      application.applicantNote!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.secondaryText,
                        height: 1.45,
                      ),
                    ),
                  if (handoffAt != null) ...[
                    const SizedBox(height: CoolSpace.x2),
                    Text(
                      'Latest handoff ${dateFormatter.format(handoffAt)} via partner route',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.info,
                        fontWeight: FontWeight.w700,
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
    final shouldOpenPartner = await showCoolBottomSheet<bool>(
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final insets = context.coolInsets;
    final loanState = report.loanApplication.state;
    final accountState = report.accountOpening.state;
    final canDiscussLoans =
        loanState == CreditReadinessState.ready ||
        loanState == CreditReadinessState.nearlyReady;
    final canStartAccount =
        accountState == CreditReadinessState.ready ||
        accountState == CreditReadinessState.nearlyReady;

    final recommendation = canDiscussLoans
        ? 'Review lending products'
        : canStartAccount
        ? 'Start savings onboarding'
        : 'Resolve profile blockers';
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
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.primaryText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x1),
                    Text(
                      partner.subtitle ??
                          partner.description ??
                          'Finance partner',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.secondaryText,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: CoolSpace.x3),
              PartnerBrandMark(
                partner: partner,
                width: 104,
                height: 52,
                padding: insets.symmetric(
                  horizontal: CoolSpace.x3,
                  vertical: CoolSpace.x2 + 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x3),
          Container(
            width: double.infinity,
            padding: insets.symmetric(
              horizontal: CoolSpace.x3 - 1,
              vertical: CoolSpace.x2 + 2,
            ),
            decoration: BoxDecoration(
              color: colors.contactSurface,
              borderRadius: const BorderRadius.all(
                Radius.circular(CoolRadii.xs),
              ),
              border: Border.all(color: colors.borderStrong),
            ),
            child: Text(
              recommendation,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.primaryText,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
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

/// Bottom-sheet for creating partner credit applications.
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final insets = context.coolInsets;
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: insets.fromLTRB(
        CoolSpace.x4,
        CoolSpace.x4,
        CoolSpace.x4,
        viewInsets + CoolSpace.x4,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.overlaySurface,
          borderRadius: const BorderRadius.all(
            Radius.circular(CoolRadii.lg - 4),
          ),
          border: Border.all(color: colors.borderStrong),
        ),
        child: SingleChildScrollView(
          padding: insets.fromLTRB(
            CoolSpace.x5 - 2,
            CoolSpace.x4,
            CoolSpace.x5 - 2,
            CoolSpace.x5 - 2,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 4,
                margin: insets.only(bottom: CoolSpace.x4),
                decoration: BoxDecoration(
                  color: colors.borderStrong,
                  borderRadius: const BorderRadius.all(
                    Radius.circular(CoolRadii.pill),
                  ),
                ),
              ),
              Text(
                'Create partner application',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: CoolSpace.x1),
              Text(
                widget.partner.name,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.info,
                ),
              ),
              const SizedBox(height: CoolSpace.x3 + 2),
              Container(
                width: double.infinity,
                padding: insets.all(CoolSpace.x3),
                decoration: BoxDecoration(
                  color: _stateColor(
                    _selectedJourney.state,
                    colors,
                  ).withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.all(
                    Radius.circular(CoolRadii.sm - 2),
                  ),
                  border: Border.all(
                    color: _stateColor(
                      _selectedJourney.state,
                      colors,
                    ).withValues(alpha: 0.22),
                  ),
                ),
                child: Text(
                  '${_selectedJourney.title}: ${_selectedJourney.summary}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.primaryText,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: CoolSpace.x4),
              DropdownButtonFormField<String>(
                initialValue: _applicationType,
                decoration: _sheetInputDecoration(
                  context,
                  label: context.l10n.applicationPath,
                ),
                items: [
                  DropdownMenuItem(
                    value: 'loan',
                    child: Text(context.l10n.loanApplication1),
                  ),
                  DropdownMenuItem(
                    value: 'account_opening',
                    child: Text(context.l10n.accountOpening),
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
              const SizedBox(height: CoolSpace.x3),
              TextFormField(
                controller: _productController,
                enabled: !_isSavingDraft && !_isSubmitting,
                decoration: _sheetInputDecoration(
                  context,
                  label: context.l10n.requestedProduct,
                  hint: 'e.g. group loan',
                ),
              ),
              const SizedBox(height: CoolSpace.x3),
              TextFormField(
                controller: _noteController,
                enabled: !_isSavingDraft && !_isSubmitting,
                maxLines: 3,
                decoration: _sheetInputDecoration(
                  context,
                  label: context.l10n.internalNote,
                  hint: 'Partner handoff notes',
                ),
              ),
              if (!_canRouteNow) ...[
                const SizedBox(height: CoolSpace.x3),
                Text(
                  'Not ready for partner',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.warning,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: CoolSpace.x4),
              Row(
                children: [
                  Expanded(
                    child: CoolButton(
                      label: context.l10n.saveDraft,
                      variant: CoolButtonVariant.secondary,
                      isLoading: _isSavingDraft,
                      onTap: _isSubmitting ? () {} : _saveDraft,
                    ),
                  ),
                  if (_canRouteNow) ...[
                    const SizedBox(width: CoolSpace.x3),
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
      final msg = submitNow ? 'Application saved' : 'Application draft saved.';
      CoolToast.success(context, msg);
      Navigator.of(context).pop(submitNow);
    } catch (error) {
      if (mounted) {
        CoolToast.error(context, 'Save failed');
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

InputDecoration _sheetInputDecoration(
  BuildContext context, {
  required String label,
  String? hint,
}) {
  final colors = context.coolSemanticColors;
  final theme = Theme.of(context);
  return InputDecoration(
    labelText: label,
    hintText: hint,
    filled: true,
    fillColor: colors.inputSurface,
    labelStyle: theme.textTheme.labelSmall?.copyWith(
      color: colors.secondaryText,
      fontWeight: FontWeight.w700,
    ),
    hintStyle: theme.textTheme.labelSmall?.copyWith(
      color: colors.tertiaryText,
      fontWeight: FontWeight.w600,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.sm - 2)),
      borderSide: BorderSide(color: colors.borderStrong),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.sm - 2)),
      borderSide: BorderSide(color: colors.info),
    ),
    border: OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.sm - 2)),
      borderSide: BorderSide(color: colors.borderStrong),
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

String _recommendedApplicationType(CreditReadinessReport report) {
  if (report.loanApplication.state == CreditReadinessState.ready ||
      report.loanApplication.state == CreditReadinessState.nearlyReady) {
    return 'loan';
  }
  return 'account_opening';
}

Color _applicationStatusColor(String status, CoolSemanticColors colors) {
  return switch (status) {
    'draft' => colors.tertiaryText,
    'partner_routed' => colors.info,
    'in_review' => colors.warning,
    'partner_contacted' => colors.accent,
    'closed' => colors.secondaryText,
    'cancelled' => colors.danger,
    _ => colors.tertiaryText,
  };
}

Color _stateColor(CreditReadinessState state, CoolSemanticColors colors) {
  return switch (state) {
    CreditReadinessState.ready => colors.accent,
    CreditReadinessState.nearlyReady => colors.info,
    CreditReadinessState.building => colors.warning,
    CreditReadinessState.actionNeeded => colors.danger,
  };
}
