import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_screen_background.dart';
import '../../../../shared/widgets/cool_toast.dart';
import '../../../auth/models/user_profile.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../widgets/bank_partner_config.dart';
import '../../../../core/l10n/l10n.dart';

enum BankOnboardingType { loan, account }

class BankOnboardingScreen extends ConsumerStatefulWidget {
  const BankOnboardingScreen({
    required this.slug,
    required this.type,
    super.key,
  });

  final String slug;
  final BankOnboardingType type;

  @override
  ConsumerState<BankOnboardingScreen> createState() =>
      _BankOnboardingScreenState();
}

class _BankOnboardingScreenState extends ConsumerState<BankOnboardingScreen> {
  int _currentStep = 0;
  String? _selfiePath;
  final _amountController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _nextStep() {
    setState(() {
      _currentStep++;
    });
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
    } else {
      context.pop();
    }
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);

    // Simulate API call to submit application
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() => _isSubmitting = false);
      CoolToast.success(
        context,
        widget.type == BankOnboardingType.loan
            ? 'Loan application sent to ${bankConfigForSlug(widget.slug).name}'
            : 'Account opening request sent to ${bankConfigForSlug(widget.slug).name}',
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final user = ref.watch(currentUserProvider);
    final config = bankConfigForSlug(widget.slug);

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return CoolScreenBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            tooltip: context.l10n.back,
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: _previousStep,
          ),
          title: Text(
            widget.type == BankOnboardingType.loan
                ? 'Loan Application'
                : 'Open Account',
            style: GoogleFonts.dmSans(
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          centerTitle: true,
        ),
        body: Column(
          children: [
            _buildStepIndicator(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _buildCurrentStep(user, config),
              ),
            ),
            _buildBottomAction(),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    final totalSteps = widget.type == BankOnboardingType.loan ? 3 : 2;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
      child: Row(
        children: List.generate(totalSteps, (index) {
          final colors = context.coolSemanticColors;
          final isActive = index <= _currentStep;
          return Expanded(
            child: Container(
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isActive ? colors.accent : colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCurrentStep(UserProfile user, BankPartnerConfig config) {
    if (_currentStep == 0) {
      return _buildKycReview(user);
    } else if (_currentStep == 1) {
      if (widget.type == BankOnboardingType.loan) {
        return _buildLoanDetails();
      } else {
        return _buildSelfieStep();
      }
    } else if (_currentStep == 2) {
      return _buildSelfieStep();
    }
    return const SizedBox.shrink();
  }

  Widget _buildKycReview(UserProfile user) {
    final colors = context.coolSemanticColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Review your KYC details',
          style: GoogleFonts.dmSans(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'These details will be',
          style: GoogleFonts.dmSans(fontSize: 14, color: colors.secondaryText),
        ),
        const SizedBox(height: 24),
        CoolCard(
          child: Column(
            children: [
              _buildInfoRow(
                Icons.person_outline,
                'Legal Name',
                user.officialName ?? user.fullName,
              ),
              const Divider(height: 32),
              _buildInfoRow(Icons.phone_outlined, 'Phone Number', user.phone),
              const Divider(height: 32),
              _buildInfoRow(
                Icons.verified_user_outlined,
                'KYC Status',
                user.kycStatus.toUpperCase(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'If these details are',
          style: GoogleFonts.dmSans(
            fontSize: 12,
            color: colors.warning,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildLoanDetails() {
    final colors = context.coolSemanticColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Needed amount',
          style: GoogleFonts.dmSans(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter the amount you',
          style: GoogleFonts.dmSans(fontSize: 14, color: colors.secondaryText),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Amount (RWF)',
            hintText: context.l10n.eg50000,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            prefixIcon: const Icon(Icons.money),
          ),
        ),
      ],
    );
  }

  Widget _buildSelfieStep() {
    final colors = context.coolSemanticColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Verification Selfie',
          style: GoogleFonts.dmSans(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Take clear selfie',
          style: GoogleFonts.dmSans(fontSize: 14, color: colors.secondaryText),
        ),
        const SizedBox(height: 32),
        Center(
          child: GestureDetector(
            onTap: () async {
              final result = await context.push(AppRoutes.kycSelfie);
              if (result is String) {
                setState(() {
                  _selfiePath = result;
                });
              }
            },
            child: Container(
              width: 200,
              height: 260,
              decoration: BoxDecoration(
                color: colors.cardSurface,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: _selfiePath != null ? colors.accent : colors.border,
                  width: 2,
                ),
                image: _selfiePath != null
                    ? DecorationImage(
                        image: FileImage(File(_selfiePath!)),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: _selfiePath == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.camera_alt_rounded,
                          size: 40,
                          color: colors.tertiaryText,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Tap to take selfie',
                          style: TextStyle(color: colors.tertiaryText),
                        ),
                      ],
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    final colors = context.coolSemanticColors;
    return Row(
      children: [
        Icon(icon, color: colors.accent, size: 20),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                color: colors.tertiaryText,
              ),
            ),
            Text(
              value,
              style: GoogleFonts.dmSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBottomAction() {
    final totalSteps = widget.type == BankOnboardingType.loan ? 3 : 2;
    final isLastStep = _currentStep == totalSteps - 1;

    bool canProceed = true;
    if (_currentStep == 0) {
      canProceed = true;
    } else if (widget.type == BankOnboardingType.loan && _currentStep == 1) {
      canProceed = _amountController.text.isNotEmpty;
    } else if (isLastStep) {
      canProceed = _selfiePath != null;
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: CoolButton(
        label: isLastStep ? 'Submit Application' : 'Continue',
        isLoading: _isSubmitting,
        onTap: canProceed ? (isLastStep ? () => _submit() : _nextStep) : () {},
      ),
    );
  }
}
